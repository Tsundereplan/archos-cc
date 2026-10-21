--[[
    sbin/updater.lua  —  ArchOS-CC Updater
    ====================================
    Called from /startup.lua when /tmp/update.pending is detected.

    Reads the pending update file (which contains the repo URL, target
    version, and file list), downloads each file from the repo, replaces
    the local copies, and reboots into the new version.

    Format of /tmp/update.pending:
        repo=<raw github URL, ending with />
        version=<new version string>
        files=
        <relative path 1>
        <relative path 2>
        ...

    Each file is fetched from <repo>/<path> and written to /<path>.
]]

local function setColor(c)
    if c and term.isColor() then
        pcall(function() term.setTextColor(c) end)
    end
end

-- Default repo URL (used as fallback if /tmp/update.pending has no repo= line)
local DEFAULT_RAW = "https://raw.githubusercontent.com/Tsundereplan/archos-cc/main/"

local function fetchURL(url, timeoutSec)
    timeoutSec = timeoutSec or 15
    if not http then return nil, "no http API" end
    http.request(url)
    local timer = os.startTimer(timeoutSec)
    while true do
        local ev = { os.pullEvent() }
        if ev[1] == "http_success" and ev[2] == url then
            local handle = ev[3]
            if handle then
                local body = handle.readAll()
                handle.close()
                os.cancelTimer(timer)
                return body
            end
            os.cancelTimer(timer)
            return nil
        elseif ev[1] == "http_failure" and ev[2] == url then
            os.cancelTimer(timer)
            return nil, ev[3] or "request failed"
        elseif ev[1] == "timer" and ev[2] == timer then
            return nil, "timeout"
        end
    end
end

local function writeFile(path, content)
    local dir = fs.getDir(path)
    if dir and dir ~= "" and dir ~= "/" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    local f = fs.open(path, "w")
    if not f then return false, "cannot open " .. path end
    f.write(content)
    f.close()
    return true
end

local function main()
    if not fs.exists("/tmp/update.pending") then
        setColor(colors.yellow)
        print("[updater] No pending update found.")
        return 0
    end

    -- Parse the pending file
    local f = fs.open("/tmp/update.pending", "r")
    if not f then
        setColor(colors.red)
        print("[updater] Cannot read /tmp/update.pending")
        return 1
    end
    local content = f.readAll()
    f.close()

    local repoURL = DEFAULT_RAW
    local newVersion = "?"
    local files = {}
    local inFiles = false
    for rawLine in content:gmatch("[^\r\n]+") do
        local line = rawLine:gsub("^%s+", ""):gsub("%s+$", "")
        if line:sub(1, 5) == "repo=" then
            repoURL = line:sub(6)
            inFiles = false
        elseif line:sub(1, 8) == "version=" then
            newVersion = line:sub(9)
            inFiles = false
        elseif line == "files=" then
            inFiles = true
        elseif inFiles and line ~= "" then
            table.insert(files, line)
        end
    end

    if not repoURL or repoURL == "" then
        setColor(colors.red)
        print("[updater] No repo URL in update.pending")
        return 1
    end
    if repoURL:sub(-1) ~= "/" then repoURL = repoURL .. "/" end

    -- Banner
    setColor(colors.lightBlue)
    print("")
    print("    ArchOS-CC Updater")
    print("    ==================")
    setColor(colors.gray)
    print("  Target version: " .. newVersion)
    print("  Files to update: " .. #files)
    print("  Repo: " .. repoURL)
    setColor(colors.white)
    print("")

    -- Pre-flight: check disk space before downloading anything.
    -- CC:Tweaked computers have ~1MB total. We don't want to download
    -- 5 files and crash on the 3rd because the disk filled up.
    local freeSpace = fs.getFreeSpace("/")
    setColor(colors.gray)
    print("  Free disk space: " .. tostring(freeSpace) .. " bytes")
    -- Rough estimate: each file is ~5-20KB. Be conservative.
    local estimatedNeed = #files * 30000  -- 30KB per file worst case
    if freeSpace and freeSpace < estimatedNeed then
        setColor(colors.red)
        print("")
        print("  [!] LOW DISK SPACE")
        print("  Need ~" .. estimatedNeed .. " bytes for " .. #files .. " files")
        print("  Have only " .. freeSpace .. " bytes free")
        print("")
        setColor(colors.yellow)
        print("  Suggestions to free space:")
        print("    fs.delete('/backup')          -- remove old backups")
        print("    fs.delete('/startup.lua.bak') -- remove old startup backup")
        print("    fs.delete('/installer.lua')   -- remove installer")
        print("    fs.delete('/var/cache/pacman')-- remove package cache")
        print("")
        setColor(colors.white)
        print("  After freeing space, run 'update install' again.")
        print("")
        -- Remove the pending file so we don't loop on every boot
        fs.delete("/tmp/update.pending")
        print("[updater] Update aborted due to low disk space.")
        print("  Booting normally in 5 seconds...")
        os.sleep(5)
        return 1
    end
    setColor(colors.green)
    print("  Disk space OK")
    setColor(colors.white)
    print("")

    -- Download each file
    -- Strategy: download the new content first, THEN delete the old file,
    -- THEN write the new one. This way:
    --   * If download fails, the old file is preserved (no data loss).
    --   * If we run out of disk space, we don't lose the old version.
    --   * Old stale content (longer than new) doesn't leak into new file.
    local ok, fail = 0, 0
    local abort = false
    for i, rel in ipairs(files) do
        if abort then break end
        setColor(colors.cyan)
        local counter = string.format("[%d/%d]", i, #files)
        print("  " .. counter .. " " .. rel)
        setColor(colors.gray)
        term.write("    > downloading ")
        local body = fetchURL(repoURL .. rel)
        if body then
            -- Check if we have enough space for this specific file
            -- (we need to hold both the old file AND the new content
            -- temporarily, so check for #body + oldSize + overhead)
            local destPath = "/" .. rel
            local oldSize = 0
            if fs.exists(destPath) and not fs.isDir(destPath) then
                local szOk, sz = pcall(fs.getSize, destPath)
                if szOk then oldSize = sz end
            end
            local fileSpace = #body + oldSize + 200  -- overhead
            local currentFree = fs.getFreeSpace(fs.getDir(destPath) or "/")
            if currentFree and currentFree < #body + 100 then
                -- Even without keeping old file, we don't have enough space
                setColor(colors.red)
                print(" FAIL: out of disk space")
                print("    need " .. (#body + 100) .. " bytes, have " .. currentFree)
                fail = fail + 1
                abort = true  -- stop the whole update; can't continue
            else
                -- Download succeeded. Now delete the old file (if any)
                -- and write the new content.
                if fs.exists(destPath) then
                    pcall(fs.delete, destPath)
                end
                -- Make sure parent directory exists
                local dir = fs.getDir(destPath)
                if dir and dir ~= "" and dir ~= "/" and not fs.exists(dir) then
                    pcall(fs.makeDir, dir)
                end
                -- Write the new file
                local f = fs.open(destPath, "w")
                if f then
                    f.write(body)
                    f.close()
                    setColor(colors.green)
                    print(" OK (" .. #body .. " B)")
                    ok = ok + 1
                else
                    setColor(colors.red)
                    print(" FAIL: cannot write " .. destPath)
                    fail = fail + 1
                end
            end
        else
            setColor(colors.red)
            print(" FAIL: download failed")
            fail = fail + 1
        end
        setColor(colors.white)
        os.sleep(0)
    end

    -- If we aborted mid-way, clean up and bail
    if abort then
        print("")
        setColor(colors.red)
        print("[updater] Update aborted - out of disk space.")
        print("  " .. ok .. " files updated successfully, " .. fail .. " failed.")
        print("")
        setColor(colors.yellow)
        print("  WARNING: System is in a partially-updated state.")
        print("  Some files are new version, others are still old.")
        print("  This may cause compatibility issues.")
        print("")
        print("  Recommended actions:")
        print("    1. Free up disk space (run 'cleanup --force' or delete /backup)")
        print("    2. Re-run 'update install' to finish the update")
        print("    3. If system is broken, restore from backup:")
        print("       cp -r /backup/archos-*/* /")
        print("")
        -- Remove the pending file so we don't loop on every boot
        fs.delete("/tmp/update.pending")
        setColor(colors.white)
        print("[updater] Booting normally in 5 seconds...")
        os.sleep(5)
        return 1
    end

    print("")
    setColor(colors.lightBlue)
    print("  ============================================")
    setColor(colors.green)
    print(string.format("  Updated: %d files", ok))
    if fail > 0 then
        setColor(colors.red)
        print(string.format("  Failed:  %d files", fail))
    end
    setColor(colors.lightBlue)
    print("  ============================================")
    setColor(colors.white)
    print("")

    -- Update /etc/version
    local vf = fs.open("/etc/version", "w")
    if vf then vf.write(newVersion); vf.close() end

    -- Remove the pending file
    fs.delete("/tmp/update.pending")

    if fail > 0 and ok == 0 then
        setColor(colors.red)
        print("[updater] All files failed. Update aborted.")
        print("  Check your internet connection or repo URL.")
        setColor(colors.white)
        os.sleep(5)
        return 1
    end

    setColor(colors.green)
    print("[updater] Update complete! Rebooting in 3 seconds ...")
    setColor(colors.white)
    os.sleep(3)
    os.reboot()
end

return main()
