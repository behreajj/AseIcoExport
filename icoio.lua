--[[
    Wikipedia
    https://en.wikipedia.org/wiki/ICO_(file_format)

    "The evolution of the ICO file format" by Raymond Chen
    https://devblogs.microsoft.com/oldnewthing/20101018-00/?p=12513
    https://devblogs.microsoft.com/oldnewthing/20101019-00/?p=12503
    https://devblogs.microsoft.com/oldnewthing/20101021-00/?p=12483
    https://devblogs.microsoft.com/oldnewthing/20101022-00/?p=12473

    Ani format
    https://www.informit.com/articles/article.aspx?p=1189080&seqNum=3
]]

local importFileExts <const> = { "cur", "ico" }
local exportFileExts <const> = { "cur", "ico" }
local visualTargets <const> = { "CANVAS", "LAYER", "SELECTION", "SLICES" }
local frameTargets <const> = { "ACTIVE", "ALL", "TAG" }

local defaults <const> = {
    -- TODO: Look into support for ani?
    fps = 12,
    visualTarget = "CANVAS",
    frameTarget = "ALL",
    wLimit = 256,
    hLimit = 256
}

---@param x integer input value
---@return integer
local function nextPowerOf2(x)
    if x ~= 0 then
        local xSgn = 1
        local xAbs = x
        if x < 0 then
            xAbs = -x
            xSgn = -1
        end
        local p = 1
        while p < xAbs do
            p = p << 1
        end
        return p * xSgn
    end
    return 0
end

---@param pivotPreset integer
---@param wMask integer
---@param hMask integer
---@return integer
---@return integer
local function pivotPresetToCoords(pivotPreset, wMask, hMask)
    if pivotPreset == 0 then
        return 0, 0
    elseif pivotPreset == 1 then
        return wMask // 2, 0
    elseif pivotPreset == 2 then
        return wMask - 1, 0
    elseif pivotPreset == 3 then
        return 0, hMask // 2
    elseif pivotPreset == 4 then
        return wMask // 2, hMask // 2
    elseif pivotPreset == 5 then
        return wMask - 1, hMask // 2
    elseif pivotPreset == 6 then
        return 0, hMask - 1
    elseif pivotPreset == 7 then
        return wMask // 2, hMask - 1
    elseif pivotPreset == 8 then
        return wMask - 1, hMask - 1
    end
    return wMask // 2, hMask // 2
end

---@param chosenImages Image[]
---@param chosenPalettes Palette[]
---@param colorModeSprite ColorMode
---@param alphaIndexSprite integer
---@param extIsCur boolean
---@param pivotPreset integer
---@return string
local function writeIco(
    chosenImages,
    chosenPalettes,
    colorModeSprite,
    alphaIndexSprite,
    extIsCur,
    pivotPreset)
    -- Cache methods.
    local ceil <const> = math.ceil
    local strbyte <const> = string.byte
    local strpack <const> = string.pack
    local tconcat <const> = table.concat

    local lenChosenImages = #chosenImages

    ---@type string[]
    local entryHeaders <const> = {}

    ---@type string[]
    local imageEntries <const> = {}

    -- The overall header is 6 bytes,
    -- each ico entry is 16 bytes.
    local icoOffset = 6 + lenChosenImages * 16

    -- Threshold for alpha at or below which mask is set to ignore.
    -- If you wanted to support, e.g., 24 bit in the future, this would
    -- determine when 1 bit alpha is set to opaque or transparent.
    local maskThreshold <const> = 0

    local k = 0
    while k < lenChosenImages do
        k = k + 1
        local image <const> = chosenImages[k]
        local palette <const> = chosenPalettes[k]

        local specImage <const> = image.spec
        local wImage <const> = specImage.width
        local hImage <const> = specImage.height

        -- Size 256 is written as 0.
        local w8 <const> = wImage >= 256 and 0 or wImage
        local h8 <const> = hImage >= 256 and 0 or hImage
        -- Bitmap height is 2x, because the transparency mask is written
        -- after the color mask.
        local hImage2 <const> = hImage + hImage
        local areaWrite <const> = wImage * hImage

        -- To support indexed color mode, numColors would have to be set
        -- to the palette length.
        local dWordsPerRow <const> = ceil(wImage / 32)
        local lenDWords <const> = dWordsPerRow * hImage
        local icoSize <const> = 40
            + areaWrite * 4 -- 4 bytes per pixel
            + lenDWords * 4 -- 4 bytes per dword

        local xHotSpot = 1  -- or bit planes for ico
        local yHotSpot = 32 -- or bits per pixel for ico
        if extIsCur then
            xHotSpot, yHotSpot = pivotPresetToCoords(
                pivotPreset, wImage, hImage)
        end

        local entryHeader <const> = strpack(
            "B B B B <I2 <I2 <I4 <I4",
            w8,        -- 1 bytes, image width
            h8,        -- 1 bytes, image height
            0,         -- 1 bytes, color count, 0 if gt 256
            0,         -- 1 bytes, reserved
            xHotSpot,  -- 2 bytes, number of planes (ico), x hotspot (cur)
            yHotSpot,  -- 2 bytes, bits per pixel (ico), y hotspot (cur)
            icoSize,   -- 4 bytes, chunk size including header
            icoOffset) -- 4 bytes, chunk offset
        entryHeaders[k] = entryHeader
        icoOffset = icoOffset + icoSize

        -- For pels per meter discussion, see
        -- https://stackoverflow.com/questions/17550545/bmp-image-header-bixpelspermeter
        local bmpHeader <const> = strpack(
            "<I4 <I4 <I4 <I2 <I2 <I4 <I4 <I4 <I4 <I4 <I4",
            40,      -- 4 bytes, header size
            wImage,  -- 4 bytes, image width
            hImage2, -- 4 bytes, image height * 2
            1,       -- 2 bytes, number of planes
            32,      -- 2 bytes, bits per pixel
            0,       -- 4 bytes, compression (unused)
            0,       -- 4 bytes, chunk size excluding header (?)
            0,       -- 4 bytes, x resolution (unused)
            0,       -- 4 bytes, y resolution (unused)
            0,       -- 4 bytes, used colors (unused)
            0)       -- 4 bytes, important colors (unused)

        local srcByteStr <const> = image.bytes
        ---@type string[]
        local trgColorBytes <const> = {}

        -- Wikipedia: "The mask has to align to a DWORD (32 bits) and
        -- should be packed with 0s. A 0 pixel means 'the corresponding
        -- pixel in the image will be drawn' and a 1 means 'ignore this
        -- pixel'."

        ---@type integer[]
        local dWords <const> = {}
        local p = 0
        while p < lenDWords do
            p = p + 1
            dWords[p] = 0
        end

        -- In bitmap format, y axis is from bottom to top.
        if colorModeSprite == ColorMode.RGB then
            local m = 0
            while m < areaWrite do
                local x <const> = m % wImage
                local y <const> = m // wImage

                local yFlipped <const> = hImage - 1 - y
                local n <const> = yFlipped * wImage + x
                local n4 <const> = n * 4

                local r8, g8, b8, a8 <const> = strbyte(
                    srcByteStr, 1 + n4, 4 + n4)
                if a8 <= maskThreshold then
                    r8 = 0
                    g8 = 0
                    b8 = 0
                end

                trgColorBytes[1 + m] = strpack("B B B B", b8, g8, r8, a8)

                local draw <const> = a8 <= maskThreshold and 1 or 0
                local xDWord <const> = x // 32
                local xBit <const> = 31 - x % 32
                local idxDWord <const> = y * dWordsPerRow + xDWord
                local dWord <const> = dWords[1 + idxDWord]
                dWords[1 + idxDWord] = dWord | (draw << xBit)

                m = m + 1
            end
        elseif colorModeSprite == ColorMode.GRAY then
            local m = 0
            while m < areaWrite do
                local x <const> = m % wImage
                local y <const> = m // wImage

                local yFlipped <const> = hImage - 1 - y
                local n <const> = yFlipped * wImage + x
                local n2 <const> = n * 2

                local v8, a8 <const> = strbyte(srcByteStr, 1 + n2, 2 + n2)
                if a8 <= maskThreshold then
                    v8 = 0
                end

                trgColorBytes[1 + m] = strpack("B B B B", v8, v8, v8, a8)

                local draw <const> = a8 <= maskThreshold and 1 or 0
                local xDWord <const> = x // 32
                local xBit <const> = 31 - x % 32
                local idxDWord <const> = y * dWordsPerRow + xDWord
                local dWord <const> = dWords[1 + idxDWord]
                dWords[1 + idxDWord] = dWord | (draw << xBit)

                m = m + 1
            end
        elseif colorModeSprite == ColorMode.INDEXED then
            local m = 0
            while m < areaWrite do
                local x <const> = m % wImage
                local y <const> = m // wImage

                local yFlipped <const> = hImage - 1 - y
                local n <const> = yFlipped * wImage + x

                local r8 = 0
                local g8 = 0
                local b8 = 0
                local a8 = 0

                local idx <const> = strbyte(srcByteStr, 1 + n)
                if idx ~= alphaIndexSprite then
                    local aseColor <const> = palette:getColor(idx)
                    a8 = aseColor.alpha
                    if a8 > maskThreshold then
                        r8 = aseColor.red
                        g8 = aseColor.green
                        b8 = aseColor.blue
                    end
                end

                trgColorBytes[1 + m] = strpack("B B B B", b8, g8, r8, a8)

                local draw <const> = a8 <= maskThreshold and 1 or 0
                local xDWord <const> = x // 32
                local xBit <const> = 31 - x % 32
                local idxDWord <const> = y * dWordsPerRow + xDWord
                local dWord <const> = dWords[1 + idxDWord]
                dWords[1 + idxDWord] = dWord | (draw << xBit)

                m = m + 1
            end
        end

        ---@type string[]
        local maskBytes <const> = {}
        local q = 0
        while q < lenDWords do
            q = q + 1
            -- This uses the reverse byte order due to how mask words
            -- were written above.
            maskBytes[q] = strpack(">I4", dWords[q])
        end

        -- To support indexed color mode, the palette would be written
        -- after the bmp header.
        local imageEntry <const> = tconcat({
            bmpHeader,
            tconcat(trgColorBytes),
            tconcat(maskBytes)
        })
        imageEntries[k] = imageEntry
    end

    local icoHeader <const> = strpack(
        "<I2 <I2 <I2",
        0,                   -- reserved
        extIsCur and 2 or 1, -- 1 is for icon, 2 is for cursor
        lenChosenImages)
    local finalString <const> = tconcat({
        icoHeader,
        tconcat(entryHeaders),
        tconcat(imageEntries)
    })
    return finalString
end

local dlg <const> = Dialog { title = "Ico Export" }

-- dlg:separator { id = "importSep" }

dlg:slider {
    id = "fps",
    label = "FPS:",
    min = 1,
    max = 60,
    value = defaults.fps,
}

dlg:newrow { always = false }

dlg:file {
    id = "importFilepath",
    label = "Open:",
    filetypes = importFileExts,
    open = true,
    focus = false,
}

dlg:newrow { always = false }

dlg:button {
    id = "importButton",
    text = "&IMPORT",
    focus = false,
    onclick = function()
        local args <const> = dlg.data
        local fps <const> = args.fps or defaults.fps --[[@as integer]]
        local importFilepath <const> = args.importFilepath --[[@as string]]

        if (not importFilepath) or (#importFilepath < 1)
            or (not app.fs.isFile(importFilepath)) then
            app.alert {
                title = "Error",
                text = "Invalid file path."
            }
            return
        end

        local fileExt <const> = app.fs.fileExtension(importFilepath)
        local fileExtLc <const> = string.lower(fileExt)
        local extIsCur <const> = fileExtLc == "cur"
        local extIsIco <const> = fileExtLc == "ico"
        if (not extIsCur) and (not extIsIco) then
            app.alert {
                title = "Error",
                text = "File extension must be cur or ico."
            }
            return
        end

        local binFile <const>, err <const> = io.open(importFilepath, "rb")
        if err ~= nil then
            if binFile then binFile:close() end
            app.alert { title = "Error", text = err }
            return
        end
        if binFile == nil then return end

        -- As a precaution against crashes, do not allow slices UI interface
        -- to be active.
        local appTool <const> = app.tool
        if appTool then
            local toolName <const> = appTool.id
            if toolName == "slice" then
                app.tool = "hand"
            end
        end

        -- Preserve fore and background colors.
        local fgc <const> = app.fgColor
        app.fgColor = Color {
            r = fgc.red,
            g = fgc.green,
            b = fgc.blue,
            a = fgc.alpha
        }

        app.command.SwitchColors()
        local bgc <const> = app.fgColor
        app.fgColor = Color {
            r = bgc.red,
            g = bgc.green,
            b = bgc.blue,
            a = bgc.alpha
        }
        app.command.SwitchColors()

        local fileData <const> = binFile:read("a")
        binFile:close()

        -- Cache methods used in loops.
        local floor <const> = math.floor
        local ceil <const> = math.ceil
        local min <const> = math.min
        local strbyte <const> = string.byte
        local strfmt <const> = string.format
        local strpack <const> = string.pack
        local strsub <const> = string.sub
        local strunpack <const> = string.unpack
        local tconcat <const> = table.concat

        local icoHeaderType <const> = strunpack("<I2", strsub(fileData, 3, 4))
        local typeIsIco = icoHeaderType == 1
        local typeIsCur = icoHeaderType == 2
        if (not typeIsIco) and (not typeIsCur) then
            app.alert {
                title = "Error",
                text = "Only icons and cursors are supported."
            }
            return
        end

        local icoHeaderEntries <const> = strunpack("<I2", strsub(fileData, 5, 6))
        if icoHeaderEntries <= 0 then
            app.alert {
                title = "Error",
                text = "The file contained no icon image entries."
            }
            return
        end

        ---@type Image[]
        local images <const> = {}
        ---@type integer[]
        local xHotSpots <const> = {}
        ---@type integer[]
        local yHotSpots <const> = {}

        local wMax = -2147483648
        local hMax = -2147483648
        local colorModeRgb <const> = ColorMode.RGB
        local colorSpaceNone <const> = ColorSpace { sRGB = false }

        ---@type table<integer, integer>
        local abgr32Dict <const> = {}
        local dictCursor = 0

        local cursor = 6
        local h = 0
        while h < icoHeaderEntries do
            h = h + 1

            -- One problem causing invalid Aseprite icos is that the data
            -- size and offset are miscalculated. One way to tell that a
            -- file is Aseprite generated is that the bmpSize and dataSize
            -- will be equal. In GIMP the bmpSize will be zero. In case it's
            -- ever worth recalculating the sizes, they don't use the
            -- const modifier.

            local icoWidth,
            icoHeight,
            numColors,
            reserved <const>,
            xHotSpot <const>, -- or bit planes for icos
            yHotSpot <const>, -- or bits per pixel for icos
            dataSize,
            dataOffset = strunpack(
                "B B B B <I2 <I2 <I4 <I4",
                strsub(fileData, cursor + 1, cursor + 16))

            if icoWidth == 0 then icoWidth = 256 end
            if icoHeight == 0 then icoHeight = 256 end
            if numColors == 0 then numColors = 256 end

            -- print(h)
            -- print(string.format("icoWidth: %d, icoHeight: %d", icoWidth, icoHeight))
            -- print(string.format("numColors: %d", numColors))
            -- print(string.format("reserved: %d", reserved))
            -- print(string.format("icoPlanes: %d, icoBpp: %d", icoPlanes, icoBpp))
            -- print(string.format("dataSize: %d, dataOffset: %d", dataSize, dataOffset))

            -- bmpSize is apparently not used vs. ico dataSize?
            local bmpHeaderSize <const>,
            bmpWidth <const>,
            bmpHeight2 <const>,
            bmpPlanes <const>,
            bmpBpp <const>,
            _ <const>, bmpSize <const>,
            _ <const>, _ <const>, _ <const>, _ <const> = strunpack(
                "<I4 <I4 <I4 <I2 <I2 <I4 <I4 <I4 <I4 <I4 <I4",
                strsub(fileData, dataOffset + 1, dataOffset + 40))

            -- Calculate the height here in case you want to try to verify the
            -- data size.
            local bmpHeight <const> = bmpHeight2 // 2 --[[@as integer]]
            if bmpWidth > wMax then wMax = bmpWidth end
            if bmpHeight > hMax then hMax = bmpHeight end

            -- print(string.format("bmpHeaderSize: %d", bmpHeaderSize))
            -- print(string.format("bmpWidth: %d, bmpHeight2: %d", bmpWidth, bmpHeight2))
            -- print(string.format("bmpPlanes: %d, bmpBpp: %d", bmpPlanes, bmpBpp))
            -- print(string.format("bmpSize: %d", bmpSize))

            if bmpHeaderSize ~= 40 or reserved ~= 0 then
                app.alert {
                    title = "Error",
                    text = {
                        "Found a malformed header when parsing the file.",
                        "This importer does not support Aseprite made icos,",
                        "nor does it support icos with compressed pngs."
                    }
                }
                return
            end

            -- Calculations for draw mask, with 1 bit per alpha.
            local areaImage <const> = bmpWidth * bmpHeight
            local dWordsPerRowMask <const> = ceil(bmpWidth / 32)
            local lenDWords <const> = dWordsPerRowMask * bmpHeight
            local alphaMapOffset <const> = dataOffset + dataSize - lenDWords * 4
            -- print(string.format("dWordsPerRowMask: %d, lenDWords: %d",
            -- dWordsPerRowMask, lenDWords))

            ---@type integer[]
            local masks <const> = {}
            local i = 0
            while i < areaImage do
                local x <const> = i % bmpWidth
                local y <const> = i // bmpWidth
                local xDWord <const> = x // 32
                local xBit <const> = 31 - x % 32
                local idxDWord <const> = 4 * (y * dWordsPerRowMask + xDWord)
                local dWord <const> = strunpack(">I4", strsub(fileData,
                    alphaMapOffset + 1 + idxDWord,
                    alphaMapOffset + 4 + idxDWord))
                local mask <const> = (dWord >> xBit) & 0x1
                masks[1 + i] = mask
                i = i + 1
            end
            -- print(tconcat(alphaMask, ", "))

            ---@type integer[]
            local palAbgr32s <const> = {}
            local numColors4 <const> = numColors * 4

            if bmpBpp <= 8 and numColors > 0 then
                local j = 0
                while j < numColors do
                    local j4 <const> = j * 4
                    local b8 <const>, g8 <const>, r8 <const> = strbyte(
                        fileData, dataOffset + 41 + j4, dataOffset + 43 + j4)
                    -- print(string.format(
                    --     "j: %d, r8: %03d, g8: %03d, b8: %03d, #%06X",
                    --     j, r8, g8, b8,
                    --     (r8 << 0x10 | g8 << 0x08 | b8)))

                    j = j + 1
                    local palAbgr32 <const> = 0xff000000 | b8 << 0x10 | g8 << 0x08 | r8
                    palAbgr32s[j] = palAbgr32
                end
            end

            ---@type string[]
            local byteStrs <const> = {}

            if bmpBpp == 8 then
                local dWordsPerRowIdx <const> = ceil(bmpWidth / 4)
                local capacityPerRowIdx <const> = 4 * dWordsPerRowIdx
                -- print(string.format("dWordsPerRowIdx: %d, capacityPerRowIdx: %d",
                --     dWordsPerRowIdx, capacityPerRowIdx))

                local k = 0
                while k < areaImage do
                    local a8 = 0
                    local b8 = 0
                    local g8 = 0
                    local r8 = 0

                    local x <const> = k % bmpWidth
                    local yFlipped <const> = k // bmpWidth

                    local mask <const> = masks[1 + k]
                    if mask == 0 then
                        a8 = 255
                        local idxMap <const> = strbyte(fileData,
                            dataOffset + 41 + numColors4
                            + yFlipped * capacityPerRowIdx + x)
                        local abgr32 <const> = palAbgr32s[1 + idxMap]
                        r8 = abgr32 & 0xff
                        g8 = (abgr32 >> 0x08) & 0xff
                        b8 = (abgr32 >> 0x10) & 0xff
                    end

                    -- print(string.format(
                    --     "bit: %d, idx: %d, r8: %03d, g8: %03d, b8: %03d, a8: %03d, #%06X",
                    --     bit, idx, r8, g8, b8, a8,
                    --     (r8 << 0x10 | g8 << 0x08 | b8)))

                    local y <const> = bmpHeight - 1 - yFlipped
                    local idxAse <const> = y * bmpWidth + x
                    byteStrs[1 + idxAse] = strpack("B B B B", r8, g8, b8, a8)

                    local abgr32 <const> = a8 << 0x18 | b8 << 0x10 | g8 << 0x08 | r8
                    if not abgr32Dict[abgr32] then
                        dictCursor = dictCursor + 1
                        abgr32Dict[abgr32] = dictCursor
                    end

                    k = k + 1
                end
            elseif bmpBpp == 24 then
                -- Wikipedia: "24 bit images are stored as B G R triples
                -- but are not DWORD aligned."
                local bmpWidth3 <const> = bmpWidth * 3
                local dWordsPerRow24 <const> = ceil(bmpWidth3 / 4)
                local capacityPerRow24 <const> = 4 * dWordsPerRow24
                -- print(string.format("dWordsPerRow24: %d, capacityPerRow24: %d",
                --     dWordsPerRow24, capacityPerRow24))

                local k = 0
                while k < areaImage do
                    local a8 = 0
                    local b8 = 0
                    local g8 = 0
                    local r8 = 0

                    local x <const> = k % bmpWidth
                    local yFlipped <const> = k // bmpWidth

                    local mask <const> = masks[1 + k]
                    if mask == 0 then
                        a8 = 255
                        local x3 <const> = x * 3
                        local offset <const> = dataOffset + 41 + yFlipped * capacityPerRow24
                        b8, g8, r8 = strbyte(fileData, offset + x3, offset + 2 + x3)
                    end

                    -- print(string.format(
                    --     "bit: %d, r8: %03d, g8: %03d, b8: %03d, #%06X",
                    --     bit, r8, g8, b8,
                    --     (r8 << 0x10 | g8 << 0x08 | b8)))

                    local y <const> = bmpHeight - 1 - yFlipped
                    local idxAse <const> = y * bmpWidth + x
                    byteStrs[1 + idxAse] = strpack("B B B B", r8, g8, b8, a8)

                    local abgr32 <const> = a8 << 0x18 | b8 << 0x10 | g8 << 0x08 | r8
                    if not abgr32Dict[abgr32] then
                        dictCursor = dictCursor + 1
                        abgr32Dict[abgr32] = dictCursor
                    end

                    k = k + 1
                end
            elseif bmpBpp == 32 then
                local k = 0
                while k < areaImage do
                    local a8 = 0
                    local b8 = 0
                    local g8 = 0
                    local r8 = 0

                    local x <const> = k % bmpWidth
                    local yFlipped <const> = k // bmpWidth

                    local mask <const> = masks[1 + k]
                    if mask == 0 then
                        local k4 <const> = 4 * k
                        b8, g8, r8, a8 = strbyte(fileData,
                            dataOffset + 41 + k4,
                            dataOffset + 44 + k4)
                    end

                    -- print(string.format(
                    --     "bit: %d, r8: %03d, g8: %03d, b8: %03d, a8: %03d, #%06X",
                    --     bit, r8, g8, b8, a8,
                    --     (r8 << 0x10 | g8 << 0x08 | b8)))

                    local y <const> = bmpHeight - 1 - yFlipped
                    local idxAse <const> = y * bmpWidth + x
                    byteStrs[1 + idxAse] = strpack("B B B B", r8, g8, b8, a8)

                    local abgr32 <const> = a8 << 0x18 | b8 << 0x10 | g8 << 0x08 | r8
                    if not abgr32Dict[abgr32] then
                        dictCursor = dictCursor + 1
                        abgr32Dict[abgr32] = dictCursor
                    end

                    k = k + 1
                end
            end

            local imageSpec <const> = ImageSpec {
                width = bmpWidth,
                height = bmpHeight,
                colorMode = colorModeRgb,
                transparentColor = 0
            }
            imageSpec.colorSpace = colorSpaceNone
            local image <const> = Image(imageSpec)
            image.bytes = tconcat(byteStrs)

            images[h] = image
            xHotSpots[h] = xHotSpot
            yHotSpots[h] = yHotSpot

            cursor = cursor + 16
            -- print(string.format("cursor: %d\n", cursor))
        end

        if wMax <= 0 or hMax <= 0 then
            app.alert {
                title = "Error",
                text = "The size of the new sprite is invalid."
            }
            return
        end

        local spriteSpec <const> = ImageSpec {
            width = wMax,
            height = hMax,
            colorMode = colorModeRgb,
            transparentColor = 0
        }
        spriteSpec.colorSpace = colorSpaceNone
        local sprite <const> = Sprite(spriteSpec)

        app.transaction("Set sprite file name", function()
            sprite.filename = app.fs.fileName(importFilepath)
        end)

        local lenImages <const> = #images

        app.transaction("Create frames", function()
            local m = 1
            while m < lenImages do
                m = m + 1
                sprite:newEmptyFrame()
            end
        end)

        app.transaction("Set frame duration", function()
            local dur <const> = 1.0 / math.max(1, fps)
            local spriteFrames <const> = sprite.frames
            local n = 0
            while n < lenImages do
                n = n + 1
                spriteFrames[n].duration = dur
            end
        end)

        local layer <const> = sprite.layers[1]
        local pointZero <const> = Point(0, 0)

        app.transaction("Create cels", function()
            local n = 0
            while n < lenImages do
                n = n + 1
                local image <const> = images[n]
                sprite:newCel(layer, n, image, pointZero)
            end
        end)

        ---@type integer[]
        local uniqueColors <const> = {}
        -- Ensure that alpha mask is at zero.
        abgr32Dict[0] = -1
        for abgr32, _ in pairs(abgr32Dict) do
            uniqueColors[#uniqueColors + 1] = abgr32
        end

        table.sort(uniqueColors, function(a, b)
            return abgr32Dict[a] < abgr32Dict[b]
        end)

        local lenUniqueColors <const> = #uniqueColors
        local lenPalette <const> = min(256, lenUniqueColors)

        local spritePalette <const> = sprite.palettes[1]

        app.transaction("Set palette", function()
            spritePalette:resize(lenPalette)
            local o = 0
            while o < lenPalette do
                local abgr32 <const> = uniqueColors[1 + o]
                local aseColor <const> = Color {
                    r = abgr32 & 0xff,
                    g = (abgr32 >> 0x08) & 0xff,
                    b = (abgr32 >> 0x10) & 0xff,
                    a = (abgr32 >> 0x18) & 0xff
                }
                spritePalette:setColor(o, aseColor)
                o = o + 1
            end
        end)

        -- Set preferences in new document that minimize bugs.
        local appPrefs <const> = app.preferences
        if appPrefs then
            local docPrefs <const> = appPrefs.document(sprite)
            if docPrefs then
                local onionSkinPrefs <const> = docPrefs.onionskin
                if onionSkinPrefs then
                    onionSkinPrefs.loop_tag = false
                end

                local thumbPrefs <const> = docPrefs.thumbnails
                if thumbPrefs then
                    thumbPrefs.enabled = true
                    thumbPrefs.zoom = 1
                    thumbPrefs.overlay_enabled = true
                end
            end
        end

        if typeIsCur then
            local r01Orig <const> = 1.0 ^ 2.2
            local g01Orig <const> = 0.0 ^ 2.2
            local b01Orig <const> = 0.0 ^ 2.2

            local r01Dest <const> = 0.0 ^ 2.2
            local g01Dest <const> = 1.0 ^ 2.2
            local b01Dest <const> = 0.0 ^ 2.2

            local nToFac <const> = lenImages > 1
                and 1.0 / (lenImages - 1.0)
                or 0.0
            local expInvert <const> = 1.0 / 2.2

            app.transaction("Create slices", function()
                local n = 0
                while n < lenImages do
                    local t <const> = n * nToFac
                    local u <const> = 1.0 - t

                    n = n + 1
                    local image <const> = images[n]
                    local xHotSpot <const> = xHotSpots[n]
                    local yHotSpot <const> = yHotSpots[n]

                    local rMixLin = u * r01Orig + t * r01Dest
                    local gMixLin = u * g01Orig + t * g01Dest
                    local bMixLin = u * b01Orig + t * b01Dest

                    -- Convert mixed color from linear to standard.
                    local rMixStd = rMixLin ^ expInvert
                    local gMixStd = gMixLin ^ expInvert
                    local bMixStd = bMixLin ^ expInvert

                    local specImage <const> = image.spec
                    local wImage <const> = specImage.width
                    local hImage <const> = specImage.height

                    local sliceBounds = Rectangle(0, 0, wImage, hImage)
                    local slice <const> = sprite:newSlice(sliceBounds)

                    slice.name = strfmt("Cursor %d", n)
                    slice.color = Color {
                        r = floor(rMixStd * 255.0 + 0.5),
                        g = floor(gMixStd * 255.0 + 0.5),
                        b = floor(bMixStd * 255.0 + 0.5),
                        a = 255
                    }
                    slice.pivot = Point(xHotSpot, yHotSpot)
                    slice.center = sliceBounds
                end
            end)
        end

        app.layer = layer
        app.frame = sprite.frames[1]
        app.sprite = sprite
    end
}

dlg:separator { id = "exportSep" }

dlg:combobox {
    id = "visualTarget",
    label = "Target:",
    option = defaults.visualTarget,
    options = visualTargets,
    focus = false,
}

dlg:newrow { always = false }

dlg:combobox {
    id = "frameTarget",
    label = "Frames:",
    option = defaults.frameTarget,
    options = frameTargets,
    focus = false,
}

dlg:newrow { always = false }

dlg:file {
    id = "exportFilepath",
    label = "Save:",
    filetypes = exportFileExts,
    save = true,
    focus = true,
}

dlg:newrow { always = false }

dlg:button {
    id = "exportButton",
    text = "E&XPORT",
    focus = false,
    onclick = function()
        local activeSprite <const> = app.sprite
        if not activeSprite then
            app.alert {
                title = "Error",
                text = "There is no active sprite."
            }
            return
        end

        -- Unpack arguments.
        local args <const> = dlg.data
        local visualTarget <const> = args.visualTarget
            or defaults.visualTarget --[[@as string]]
        local frameTarget <const> = args.frameTarget
            or defaults.frameTarget --[[@as string]]
        local exportFilepath <const> = args.exportFilepath --[[@as string]]

        local wLimit <const> = defaults.wLimit
        local hLimit <const> = defaults.hLimit

        if (not exportFilepath) or (#exportFilepath < 1) then
            app.alert {
                title = "Error",
                text = "Invalid file path."
            }
            return
        end

        local fileExt <const> = app.fs.fileExtension(exportFilepath)
        local fileExtLc <const> = string.lower(fileExt)
        local extIsCur <const> = fileExtLc == "cur"
        local extIsIco <const> = fileExtLc == "ico"
        if (not extIsCur) and (not extIsIco) then
            app.alert {
                title = "Error",
                text = "File extension must be cur or ico."
            }
            return
        end

        ---@type Slice[]
        local chosenSlices <const> = {}

        -- Prevent uncommitted selection transformation (drop pixels) or
        -- display of sprite slices in context bar from raising an error.
        local appTool <const> = app.tool
        if appTool then
            local toolName <const> = appTool.id
            if toolName == "slice" then
                local appRange <const> = app.range
                if appRange.sprite == activeSprite then
                    local rangeSlices <const> = appRange.slices
                    local lenRangeSlices <const> = #rangeSlices
                    local g = 0
                    while g < lenRangeSlices do
                        g = g + 1
                        chosenSlices[g] = rangeSlices[g]
                    end
                end

                app.tool = "hand"
            end
        end

        -- Cache methods used in loops.
        local abs <const> = math.abs
        local max <const> = math.max
        local min <const> = math.min
        local strpack <const> = string.pack
        local strsub <const> = string.sub
        local tconcat <const> = table.concat

        -- Unpack sprite specification.
        local specSprite <const> = activeSprite.spec
        local colorModeSprite <const> = specSprite.colorMode
        local wSprite <const> = specSprite.width
        local hSprite <const> = specSprite.height
        local alphaIndexSprite <const> = specSprite.transparentColor
        local colorSpaceSprite <const> = specSprite.colorSpace

        ---@type integer[]
        local chosenFrIdcs <const> = {}
        if frameTarget == "ACTIVE" then
            local activeFrObj <const> = app.frame
                or activeSprite.frames[1]
            local activeFrIdx <const> = activeFrObj.frameNumber
            chosenFrIdcs[1] = activeFrIdx
        elseif frameTarget == "TAG" then
            local tagsSprite <const> = activeSprite.tags
            local lenTagsSprite <const> = #tagsSprite
            if lenTagsSprite <= 0 then
                app.alert {
                    title = "Error",
                    text = "Sprite does not contain any tags."
                }
                return
            end

            local spriteFrames <const> = activeSprite.frames
            local lenSpriteFrames <const> = #spriteFrames

            local activeTag <const> = app.tag or tagsSprite[1]
            local frFrameObj <const> = activeTag.fromFrame
            local toFrameObj <const> = activeTag.toFrame

            -- It has been possible for tags to be out of bounds due to
            -- export bugs.
            local frFrameIdx <const> = min(max(
                frFrameObj and frFrameObj.frameNumber or 1,
                1), lenSpriteFrames)
            local toFrameIdx <const> = min(max(
                toFrameObj and toFrameObj.frameNumber or lenSpriteFrames,
                1), lenSpriteFrames)

            local i = frFrameIdx - 1
            while i < toFrameIdx do
                i = i + 1
                chosenFrIdcs[#chosenFrIdcs + 1] = i
            end
        else
            -- Default to "ALL".
            local spriteFrames <const> = activeSprite.frames
            local lenSpriteFrames <const> = #spriteFrames
            local i = 0
            while i < lenSpriteFrames do
                i = i + 1
                chosenFrIdcs[i] = i
            end
        end

        local lenChosenFrIdcs <const> = #chosenFrIdcs
        if lenChosenFrIdcs <= 0 then
            app.alert {
                title = "Error",
                text = "No frames were chosen to export."
            }
            return
        end

        local spritePalettes <const> = activeSprite.palettes
        local lenSpritePalettes <const> = #spritePalettes

        ---@type Palette[]
        local chosenPalettes <const> = {}
        ---@type Image[]
        local chosenImages <const> = {}

        if visualTarget == "LAYER" then
            local activeLayer <const> = app.layer
                or activeSprite.layers[1]

            local isReference <const> = activeLayer.isReference
            if isReference then
                app.alert {
                    title = "Error",
                    text = "Reference layers are not supported."
                }
                return
            end

            local isTileMap <const> = activeLayer.isTilemap
            if isTileMap then
                app.alert {
                    title = "Error",
                    text = {
                        "Tile map layers are not supported.",
                        "Convert to a normal layer before proceeding."
                    }
                }
                return
            end

            local isGroup <const> = activeLayer.isGroup
            if isGroup then
                app.alert {
                    title = "Error",
                    text = {
                        "Group layers are not supported.",
                        "Flatten group before proceeding."
                    }
                }
                return
            end

            local pointZero <const> = Point(0, 0)
            local blendModeSrc <const> = BlendMode.SRC

            local j = 0
            while j < lenChosenFrIdcs do
                j = j + 1
                local chosenFrIdx <const> = chosenFrIdcs[j]

                local cel <const> = activeLayer:cel(chosenFrIdx)
                if cel then
                    local imageCel <const> = cel.image
                    local wCel <const> = imageCel.width
                    local hCel <const> = imageCel.height
                    local imageTrg = imageCel
                    -- if wCel > wLimit or hCel > hLimit then
                    local wBlit <const> = min(wLimit, nextPowerOf2(wCel))
                    local hBlit <const> = min(hLimit, nextPowerOf2(hCel))
                    local specBlit <const> = ImageSpec {
                        width = wBlit,
                        height = hBlit,
                        colorMode = colorModeSprite,
                        transparentColor = alphaIndexSprite
                    }
                    specBlit.colorSpace = colorSpaceSprite
                    local imageBlit <const> = Image(specBlit)
                    imageBlit:drawImage(imageCel, pointZero, 255, blendModeSrc)
                    imageTrg = imageBlit
                    -- end
                    chosenImages[#chosenImages + 1] = imageTrg

                    local palIdx <const> = chosenFrIdx <= lenSpritePalettes
                        and chosenFrIdx or 1
                    local palette <const> = spritePalettes[palIdx]
                    chosenPalettes[#chosenPalettes + 1] = palette
                end
            end
        elseif visualTarget == "SELECTION" then
            local mask <const> = activeSprite.selection
            if mask.isEmpty then
                app.alert {
                    title = "Error",
                    text = "Selection is empty."
                }
                return
            end

            local boundsMask <const> = mask.bounds
            local xtlBounds <const> = boundsMask.x
            local ytlBounds <const> = boundsMask.y
            local wBounds <const> = max(1, abs(boundsMask.width))
            local hBounds <const> = max(1, abs(boundsMask.height))

            local wBlit <const> = min(wLimit, nextPowerOf2(wBounds))
            local hBlit <const> = min(hLimit, nextPowerOf2(hBounds))
            local specBlit <const> = ImageSpec {
                width = wBlit,
                height = hBlit,
                colorMode = colorModeSprite,
                transparentColor = alphaIndexSprite
            }
            specBlit.colorSpace = colorSpaceSprite

            local rgba32Zero <const> = strpack("B B B B", 0, 0, 0, 0)
            local va16Zero <const> = strpack("B B", 0, 0)
            local ai8Zero <const> = strpack("B", alphaIndexSprite)
            local lenBlit <const> = wBlit * hBlit
            local pointZero <const> = Point(0, 0)

            local j = 0
            while j < lenChosenFrIdcs do
                j = j + 1
                local chosenFrIdx <const> = chosenFrIdcs[j]

                local imageBlit <const> = Image(specBlit)
                imageBlit:drawSprite(activeSprite, chosenFrIdx, pointZero)

                ---@type string[]
                local trgBytes <const> = {}
                local srcBytes <const> = imageBlit.bytes

                if colorModeSprite == ColorMode.RGB then
                    local k = 0
                    while k < lenBlit do
                        local x <const> = k % wBlit
                        local y <const> = k // wBlit
                        if mask:contains(xtlBounds + x, ytlBounds + y) then
                            local k4 <const> = k * 4
                            trgBytes[1 + k] = strsub(srcBytes, 1 + k4, 4 + k4)
                        else
                            trgBytes[1 + k] = rgba32Zero
                        end
                        k = k + 1
                    end
                elseif colorModeSprite == ColorMode.GRAY then
                    local k = 0
                    while k < lenBlit do
                        local x <const> = k % wBlit
                        local y <const> = k // wBlit
                        if mask:contains(xtlBounds + x, ytlBounds + y) then
                            local k2 <const> = k * 2
                            trgBytes[1 + k] = strsub(srcBytes, 1 + k2, 2 + k2)
                        else
                            trgBytes[1 + k] = va16Zero
                        end
                        k = k + 1
                    end
                elseif colorModeSprite == ColorMode.INDEXED then
                    local k = 0
                    while k < lenBlit do
                        local x <const> = k % wBlit
                        local y <const> = k // wBlit
                        if mask:contains(xtlBounds + x, ytlBounds + y) then
                            trgBytes[1 + k] = strsub(srcBytes, 1 + k, 1 + k)
                        else
                            trgBytes[1 + k] = ai8Zero
                        end
                        k = k + 1
                    end
                end

                imageBlit.bytes = tconcat(trgBytes)
                chosenImages[j] = imageBlit

                local palIdx <const> = chosenFrIdx <= lenSpritePalettes
                    and chosenFrIdx or 1
                local palette <const> = spritePalettes[palIdx]
                chosenPalettes[j] = palette
            end
        elseif visualTarget == "SLICES" then
            local lenChosenSlices = #chosenSlices
            if lenChosenSlices <= 0 then
                local spriteSlices <const> = activeSprite.slices
                local lenSpriteSlices <const> = #spriteSlices
                local g = 0
                while g < lenSpriteSlices do
                    g = g + 1
                    chosenSlices[g] = spriteSlices[g]
                end
                lenChosenSlices = #chosenSlices
            end

            if lenChosenSlices <= 0 then
                app.alert {
                    title = "Error",
                    text = "Sprite does not contain any slices."
                }
                return
            end

            local defaultBounds <const> = Rectangle(0, 0, wSprite, hSprite)

            -- Make the slices loop the outer loop in case a slice's frames
            -- become accessible through API in the future.
            local h = 0
            while h < lenChosenSlices do
                h = h + 1
                local slice <const> = chosenSlices[h]
                local boundsSlice <const> = slice.bounds or defaultBounds
                local xtlBounds <const> = boundsSlice.x
                local ytlBounds <const> = boundsSlice.y
                local wBounds <const> = max(1, abs(boundsSlice.width))
                local hBounds <const> = max(1, abs(boundsSlice.height))
                local blitOffset <const> = Point(-xtlBounds, -ytlBounds)

                local wBlit <const> = min(wLimit, nextPowerOf2(wBounds))
                local hBlit <const> = min(hLimit, nextPowerOf2(hBounds))
                local specBlit <const> = ImageSpec {
                    width = wBlit,
                    height = hBlit,
                    colorMode = colorModeSprite,
                    transparentColor = alphaIndexSprite
                }
                specBlit.colorSpace = colorSpaceSprite

                local j = 0
                while j < lenChosenFrIdcs do
                    j = j + 1
                    local chosenFrIdx <const> = chosenFrIdcs[j]

                    local imageBlit <const> = Image(specBlit)
                    imageBlit:drawSprite(activeSprite, chosenFrIdx, blitOffset)
                    chosenImages[#chosenImages + 1] = imageBlit

                    local palIdx <const> = chosenFrIdx <= lenSpritePalettes
                        and chosenFrIdx or 1
                    local palette <const> = spritePalettes[palIdx]
                    chosenPalettes[#chosenPalettes + 1] = palette
                end
            end
        else
            -- Default to "CANVAS"
            local pointZero <const> = Point(0, 0)
            local wBlit <const> = min(wLimit, nextPowerOf2(wSprite))
            local hBlit <const> = min(hLimit, nextPowerOf2(hSprite))
            local specBlit <const> = ImageSpec {
                width = wBlit,
                height = hBlit,
                colorMode = colorModeSprite,
                transparentColor = alphaIndexSprite
            }
            specBlit.colorSpace = colorSpaceSprite

            local j = 0
            while j < lenChosenFrIdcs do
                j = j + 1
                local chosenFrIdx <const> = chosenFrIdcs[j]

                local imageBlit <const> = Image(specBlit)
                imageBlit:drawSprite(activeSprite, chosenFrIdx, pointZero)
                chosenImages[j] = imageBlit

                local palIdx <const> = chosenFrIdx <= lenSpritePalettes
                    and chosenFrIdx or 1
                local palette <const> = spritePalettes[palIdx]
                chosenPalettes[j] = palette
            end
        end

        local lenChosenImages <const> = #chosenImages
        if lenChosenImages <= 0 then
            app.alert {
                title = "Error",
                text = "No images were chosen to export."
            }
            return
        end

        local binFile <const>, err <const> = io.open(exportFilepath, "wb")
        if err ~= nil then
            if binFile then binFile:close() end
            app.alert { title = "Error", text = err }
            return
        end
        if binFile == nil then return end

        local maskPivot = 0
        local appPrefs <const> = app.preferences
        if appPrefs then
            local maskPrefs <const> = appPrefs.selection
            if maskPrefs then
                if maskPrefs.pivot_position then
                    maskPivot = maskPrefs.pivot_position --[[@as integer]]
                end
            end
        end

        local icoString <const> = writeIco(
            chosenImages,
            chosenPalettes,
            colorModeSprite,
            alphaIndexSprite,
            extIsCur,
            maskPivot)
        binFile:write(icoString)
        binFile:close()

        app.alert {
            title = "Success",
            text = "File exported."
        }
    end
}

dlg:separator { id = "cancelSep" }

dlg:button {
    id = "cancelButton",
    text = "&CANCEL",
    focus = false,
    onclick = function()
        dlg:close()
    end
}

dlg:show { wait = false }