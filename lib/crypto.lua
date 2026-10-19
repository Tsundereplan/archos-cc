--[[
    lib/crypto.lua  —  Cryptographic helpers
    =======================================
    Pure-Lua implementations (CC:Tweaked / Lua 5.1 compatible):
      * SHA-256 (full implementation, via bit32 API)
      * SHA-1 (legacy)
      * FNV-1a (fast non-crypto hash)
      * Base64 encode/decode
      * XOR cipher (symmetric, simple)
      * RC4 (stream cipher, for demo encryption)

    IMPORTANT: CC:Tweaked uses Lua 5.1 (Cobalt), which does NOT support
    the Lua 5.3 bitwise operators (~, &, |, <<, >>). All bitwise ops
    must go through the `bit32` API. This file wraps bit32 into short
    local names at the top so the algorithm bodies below read cleanly.

    These are NOT audited for production security. They exist to give
    the OS a coherent crypto story for password hashing, signed packages,
    and encrypted home directories.
]]

local Crypto = {}

-- Bitwise helpers (Lua 5.1 / CC:Tweaked compatible via bit32).
-- bit32 is always available in CC:Tweaked. If somehow not, we fall
-- back to arithmetic implementations (slower but functional).
local bxor, band, bor, bnot, lshift, rshift, rrotate, lrotate
if bit32 then
    bxor    = bit32.bxor
    band    = bit32.band
    bor     = bit32.bor
    bnot    = bit32.bnot
    lshift  = bit32.lshift
    rshift  = bit32.rshift
    rrotate = bit32.rrotate
    lrotate = bit32.lrotate
else
    -- Arithmetic fallbacks (slow, but correct for 32-bit unsigned math)
    local mod = 4294967296  -- 2^32
    bxor = function(a, b)
        local r, p = 0, 1
        for _ = 1, 32 do
            local ab = a % 2; a = (a - ab) / 2
            local bb = b % 2; b = (b - bb) / 2
            if ab ~= bb then r = r + p end
            p = p * 2
        end
        return r
    end
    band = function(a, b)
        local r, p = 0, 1
        for _ = 1, 32 do
            local ab = a % 2; a = (a - ab) / 2
            local bb = b % 2; b = (b - bb) / 2
            if ab == 1 and bb == 1 then r = r + p end
            p = p * 2
        end
        return r
    end
    bor = function(a, b)
        local r, p = 0, 1
        for _ = 1, 32 do
            local ab = a % 2; a = (a - ab) / 2
            local bb = b % 2; b = (b - bb) / 2
            if ab == 1 or bb == 1 then r = r + p end
            p = p * 2
        end
        return r
    end
    bnot = function(a) return (mod - 1 - a) % mod end
    lshift = function(a, n)
        if n >= 32 then return 0 end
        if n <= 0 then return a % mod end
        return (a * 2^n) % mod
    end
    rshift = function(a, n)
        if n >= 32 then return 0 end
        if n <= 0 then return a % mod end
        return math.floor((a % mod) / 2^n)
    end
    rrotate = function(a, n)
        n = n % 32
        if n == 0 then return a % mod end
        return (rshift(a, n) + lshift(a, 32 - n)) % mod
    end
    lrotate = function(a, n)
        n = n % 32
        if n == 0 then return a % mod end
        return (lshift(a, n) + rshift(a, 32 - n)) % mod
    end
end

-- FNV-1a 32-bit hash
function Crypto.fnv1a(data)
    local h = 2166136261
    for i = 1, #data do
        h = bxor(h, data:byte(i))
        h = (h * 16777619) % 4294967296
    end
    return h
end

-- SHA-256 implementation
-- Standard implementation following RFC 6234
local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function sha256(msg)
    -- Initial hash values
    local H = {
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    }

    -- Pre-processing: padding
    local len = #msg
    msg = msg .. string.char(0x80)
    while #msg % 64 ~= 56 do msg = msg .. string.char(0) end
    -- Append length in bits (64-bit big-endian, we just use 32-bit)
    local lenBits = len * 8
    for i = 4, 1, -1 do
        msg = msg .. string.char(band(rshift(lenBits, (i-1) * 8), 0xFF))
    end
    msg = msg .. string.char(0, 0, 0, 0)  -- high 32 bits = 0

    -- Process each 512-bit chunk
    for chunkStart = 1, #msg, 64 do
        local W = {}
        for i = 1, 16 do
            local s = chunkStart + (i - 1) * 4
            W[i] = bor(
                lshift(msg:byte(s), 24),
                lshift(msg:byte(s+1), 16),
                lshift(msg:byte(s+2), 8),
                msg:byte(s+3)
            )
            W[i] = W[i] % 4294967296
        end
        for i = 17, 64 do
            local s0 = bxor(bxor(rrotate(W[i-15], 7), rrotate(W[i-15], 18)), rshift(W[i-15], 3))
            local s1 = bxor(bxor(rrotate(W[i-2], 17), rrotate(W[i-2], 19)), rshift(W[i-2], 10))
            W[i] = (W[i-16] + s0 + W[i-7] + s1) % 4294967296
        end

        local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
        for i = 1, 64 do
            local S1 = bxor(bxor(rrotate(e, 6), rrotate(e, 11)), rrotate(e, 25))
            local ch = bxor(band(e, f), band(bnot(e), g))
            local temp1 = (h + S1 + ch + K[i] + W[i]) % 4294967296
            local S0 = bxor(bxor(rrotate(a, 2), rrotate(a, 13)), rrotate(a, 22))
            local maj = bxor(bxor(band(a, b), band(a, c)), band(b, c))
            local temp2 = (S0 + maj) % 4294967296

            h = g; g = f; f = e
            e = (d + temp1) % 4294967296
            d = c; c = b; b = a
            a = (temp1 + temp2) % 4294967296
        end

        H[1] = (H[1] + a) % 4294967296
        H[2] = (H[2] + b) % 4294967296
        H[3] = (H[3] + c) % 4294967296
        H[4] = (H[4] + d) % 4294967296
        H[5] = (H[5] + e) % 4294967296
        H[6] = (H[6] + f) % 4294967296
        H[7] = (H[7] + g) % 4294967296
        H[8] = (H[8] + h) % 4294967296
    end

    -- Convert to hex string
    local result = ""
    for i = 1, 8 do
        result = result .. string.format("%08x", H[i])
    end
    return result
end

Crypto.sha256 = sha256

-- SHA-1 implementation (legacy)
function Crypto.sha1(msg)
    local h0, h1, h2, h3, h4 = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0

    local len = #msg
    msg = msg .. string.char(0x80)
    while #msg % 64 ~= 56 do msg = msg .. string.char(0) end
    local lenBits = len * 8
    for i = 4, 1, -1 do
        msg = msg .. string.char(band(rshift(lenBits, (i-1)*8), 0xFF))
    end
    msg = msg .. string.char(0, 0, 0, 0)

    for chunkStart = 1, #msg, 64 do
        local W = {}
        for i = 1, 16 do
            local s = chunkStart + (i-1) * 4
            W[i] = bor(
                lshift(msg:byte(s), 24),
                lshift(msg:byte(s+1), 16),
                lshift(msg:byte(s+2), 8),
                msg:byte(s+3)
            )
            W[i] = W[i] % 4294967296
        end
        for i = 17, 80 do
            W[i] = rrotate(bxor(bxor(bxor(W[i-3], W[i-8]), W[i-14]), W[i-16]), 1)
            W[i] = W[i] % 4294967296
        end

        local a, b, c, d, e = h0, h1, h2, h3, h4
        for i = 1, 80 do
            local f, k
            if i <= 20 then f = bor(band(b, c), band(bnot(b), d)); k = 0x5A827999
            elseif i <= 40 then f = bxor(bxor(b, c), d); k = 0x6ED9EBA1
            elseif i <= 60 then f = bor(bor(band(b, c), band(b, d)), band(c, d)); k = 0x8F1BBCDC
            else f = bxor(bxor(b, c), d); k = 0xCA62C1D6
            end
            local temp = (rrotate(a, 5) + f + e + k + W[i]) % 4294967296
            e = d; d = c; c = rrotate(b, 30); b = a; a = temp
        end

        h0 = (h0 + a) % 4294967296
        h1 = (h1 + b) % 4294967296
        h2 = (h2 + c) % 4294967296
        h3 = (h3 + d) % 4294967296
        h4 = (h4 + e) % 4294967296
    end

    return string.format("%08x%08x%08x%08x%08x", h0, h1, h2, h3, h4)
end

-- HMAC-SHA256
function Crypto.hmacSha256(key, message)
    local blockSize = 64
    if #key > blockSize then
        key = sha256(key)  -- hash to fit (will be 64 bytes when hex-decoded; for simplicity treat as string)
    end
    -- Pad key
    while #key < blockSize do key = key .. string.char(0) end

    local o_key_pad = ""
    local i_key_pad = ""
    for i = 1, blockSize do
        o_key_pad = o_key_pad .. string.char(bxor(key:byte(i), 0x5c))
        i_key_pad = i_key_pad .. string.char(bxor(key:byte(i), 0x36))
    end

    return sha256(o_key_pad .. sha256(i_key_pad .. message))
end

-- Base64 (delegate to cc.base64 if available)
function Crypto.base64Encode(data)
    if cc and cc.base64 then return cc.base64.encode(data) end
    -- Fallback implementation
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local out = ""
    local i = 1
    while i <= #data do
        local b1 = data:byte(i) or 0
        local b2 = data:byte(i+1) or 0
        local b3 = data:byte(i+2) or 0
        local n = bor(lshift(b1, 16), lshift(b2, 8), b3)
        local idx1 = band(rshift(n, 18), 0x3F)
        local idx2 = band(rshift(n, 12), 0x3F)
        local idx3 = band(rshift(n, 6), 0x3F)
        local idx4 = band(n, 0x3F)
        out = out .. chars:sub(idx1 + 1, idx1 + 1)
        out = out .. chars:sub(idx2 + 1, idx2 + 1)
        if i + 1 <= #data then
            out = out .. chars:sub(idx3 + 1, idx3 + 1)
        else
            out = out .. "="
        end
        if i + 2 <= #data then
            out = out .. chars:sub(idx4 + 1, idx4 + 1)
        else
            out = out .. "="
        end
        i = i + 3
    end
    return out
end

function Crypto.base64Decode(data)
    if cc and cc.base64 then return cc.base64.decode(data) end
    -- Fallback implementation
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local lookup = {}
    for i = 1, #chars do lookup[chars:byte(i)] = i - 1 end
    local out = {}
    local buffer = 0
    local bits = 0
    for i = 1, #data do
        local c = data:byte(i)
        if c ~= 61 and lookup[c] then  -- 61 is '='
            buffer = bor(lshift(buffer, 6), lookup[c])
            bits = bits + 6
            if bits >= 8 then
                bits = bits - 8
                table.insert(out, string.char(band(rshift(buffer, bits), 0xFF)))
            end
        end
    end
    return table.concat(out)
end

-- XOR cipher (symmetric, simple)
function Crypto.xorCipher(data, key)
    if not key or #key == 0 then return data end
    local out = {}
    for i = 1, #data do
        local kb = key:byte((i - 1) % #key + 1)
        out[i] = string.char(bxor(data:byte(i), kb))
    end
    return table.concat(out)
end

-- RC4 stream cipher
function Crypto.rc4(key, data)
    local S = {}
    for i = 0, 255 do S[i] = i end
    local j = 0
    for i = 0, 255 do
        j = (j + S[i] + key:byte((i % #key) + 1)) % 256
        S[i], S[j] = S[j], S[i]
    end
    local i, j = 0, 0
    local out = {}
    for n = 1, #data do
        i = (i + 1) % 256
        j = (j + S[i]) % 256
        S[i], S[j] = S[j], S[i]
        local k = S[(S[i] + S[j]) % 256]
        out[n] = string.char(bxor(data:byte(n), k))
    end
    return table.concat(out)
end

-- Random number generation (using os.clock + os.time)
function Crypto.random(max)
    local seed = os.clock() * 1000000 + os.time() * 7 + os.getComputerID()
    local h = Crypto.fnv1a(tostring(seed))
    if max then return (h % max) + 1 end
    return h
end

-- Generate a random hex string of given length
function Crypto.randomHex(length)
    local chars = "0123456789abcdef"
    local out = {}
    for i = 1, length do
        out[i] = chars:sub(Crypto.random(16), Crypto.random(16))
    end
    return table.concat(out)
end

return Crypto
