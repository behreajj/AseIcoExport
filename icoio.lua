local fileExts <const> = { "ico" }
local visualTargets <const> = { "CANVAS", "LAYER", "SELECTION" }
local frameTargets <const> = { "ACTIVE", "ALL", "TAG" }

local defaults <const> = {
    visualTarget = "CANVAS",
    frameTarget = "ALL",
}

local dlg <const> = Dialog { title = "Ico Export" }

-- dlg:separator { id = "exportSep" }

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
    filetypes = fileExts,
    save = true,
    focus = false
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

        if (not exportFilepath) or (#exportFilepath < 1) then
            app.alert {
                title = "Error",
                text = "Invalid file path."
            }
            return
        end

        local fileExt <const> = app.fs.fileExtension(exportFilepath)
        local fileExtLc <const> = string.lower(fileExt)
        if fileExtLc ~= "ico" then
            app.alert {
                title = "Error",
                text = "File format must be ico."
            }
            return
        end

        -- Prevent uncommitted selection transformation (drop pixels) or
        -- display of sprite slices in context bar from raising an error.
        local appTool <const> = app.tool
        if appTool then
            local toolName <const> = appTool.id
            if toolName == "slice" then
                app.tool = "hand"
            end
        end

        -- Cache methods used in loops.
        local abs <const> = math.abs
        local ceil <const> = math.ceil
        local max <const> = math.max
        local min <const> = math.min
        local strbyte <const> = string.byte
        local strpack <const> = string.pack
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
                    if wCel > 256 or hCel > 256 then
                        local wBlit <const> = min(256, wCel)
                        local hBlit <const> = min(256, hCel)
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
                    end
                    chosenImages[#chosenImages + 1] = imageTrg

                    local palIdx <const> = chosenFrIdx <= lenSpritePalettes
                        and chosenFrIdx or 1
                    local palette <const> = spritePalettes[palIdx]
                    chosenPalettes[#chosenPalettes + 1] = palette
                end
            end
        elseif visualTarget == "SELECTION" then
            local selection <const> = activeSprite.selection
            if selection.isEmpty then
                app.alert {
                    title = "Error",
                    text = "Selection is empty."
                }
                return
            end

            local boundsSel <const> = selection.bounds
            local xtlBounds <const> = boundsSel.x
            local ytlBounds <const> = boundsSel.y
            local originBounds <const> = Point(xtlBounds, ytlBounds)
            local wBounds <const> = max(1, abs(boundsSel.width))
            local hBounds <const> = max(1, abs(boundsSel.height))

            local wBlit <const> = min(256, wBounds)
            local hBlit <const> = min(256, hBounds)
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
                imageBlit:drawSprite(activeSprite, chosenFrIdx, originBounds)
                -- TODO: Remove pixels not in selection.
                chosenImages[j] = imageBlit

                local palIdx <const> = chosenFrIdx <= lenSpritePalettes
                    and chosenFrIdx or 1
                local palette <const> = spritePalettes[palIdx]
                chosenPalettes[j] = palette
            end
        else
            -- Default to "CANVAS"
            local pointZero <const> = Point(0, 0)
            local wBlit <const> = min(256, wSprite)
            local hBlit <const> = min(256, hSprite)
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

        ---@type string[]
        local entryHeaders <const> = {}
        ---@type string[]
        local imageEntries <const> = {}

        -- The overall header is 6 bytes,
        -- each ico entry is 16 bytes.
        local icoOffset = 6 + lenChosenImages * 16

        local k = 0
        while k < lenChosenImages do
            k = k + 1
            local image <const> = chosenImages[k]
            local palette <const> = chosenPalettes[k]

            local specImage <const> = image.spec
            local wImage <const> = specImage.width
            local hImage <const> = specImage.height

            -- Size 256 is written as 0.
            local w8 <const> = wImage % 256
            local h8 <const> = hImage % 256
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

            local entryHeader <const> = strpack(
                "B B B B <I2 <I2 <I4 <I4",
                w8,        -- 1 bytes, image width
                h8,        -- 1 bytes, image height
                0,         -- 1 bytes, number of colors, 0 if gt 256
                0,         -- 1 bytes, reserved
                1,         -- 2 bytes, number of planes
                32,        -- 2 bytes, bits per pixel
                icoSize,   -- 4 bytes, chunk size
                icoOffset) -- 4 bytes, chunk offset
            entryHeaders[k] = entryHeader
            icoOffset = icoOffset + icoSize

            local bmpHeader <const> = strpack(
                "<I4 <I4 <I4 <I2 <I2 <I4 <I4 <I4 <I4 <I4 <I4",
                40,      -- 4 bytes, header size
                wImage,  -- 4 bytes, image width
                hImage2, -- 4 bytes, image height * 2
                1,       -- 2 bytes, number of planes
                32,      -- 2 bytes, bits per pixel
                0,       -- 4 bytes
                0,       -- 4 bytes
                0,       -- 4 bytes
                0,       -- 4 bytes
                0,       -- 4 bytes
                0)       -- 4 bytes

            -- TODO: Test translucency.
            -- TODO: Test 256 x 256 image.
            local srcByteStr <const> = image.bytes
            ---@type string[]
            local trgColorBytes <const> = {}

            -- From Wikipedia:
            -- "The mask has to align to a DWORD (32 bits) and should be packed
            -- with 0s. A 0 pixel means 'the corresponding pixel in the image
            -- will be drawn' and a 1 means 'ignore this pixel'."

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

                    local r8 <const>,
                    g8 <const>,
                    b8 <const>,
                    a8 <const> = strbyte(srcByteStr, 1 + n4, 4 + n4)

                    trgColorBytes[1 + m] = strpack("B B B B", b8, g8, r8, a8)

                    local draw <const> = a8 <= 0 and 1 or 0
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

                    local v8 <const>,
                    a8 <const> = strbyte(srcByteStr, 1 + n2, 2 + n2)

                    trgColorBytes[1 + m] = strpack("B B B B", v8, v8, v8, a8)

                    local draw <const> = a8 <= 0 and 1 or 0
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
                        if a8 > 0 then
                            r8 = aseColor.red
                            g8 = aseColor.green
                            b8 = aseColor.blue
                        end
                    end

                    trgColorBytes[1 + m] = strpack("B B B B", b8, g8, r8, a8)

                    local draw <const> = a8 <= 0 and 1 or 0
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
            0, -- reserved
            1, -- 1 is for icon, 2 is for cursor
            lenChosenImages)
        local finalString <const> = tconcat({
            icoHeader,
            tconcat(entryHeaders),
            tconcat(imageEntries)
        })
        binFile:write(finalString)
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
    focus = false
}

dlg:show { wait = false }