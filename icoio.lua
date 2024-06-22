--[[
    Wikipedia
    https://en.wikipedia.org/wiki/ICO_(file_format)

    "The evolution of the ICO file format" by Raymond Chen
    https://devblogs.microsoft.com/oldnewthing/20101018-00/?p=12513
    https://devblogs.microsoft.com/oldnewthing/20101019-00/?p=12503
    https://devblogs.microsoft.com/oldnewthing/20101021-00/?p=12483
    https://devblogs.microsoft.com/oldnewthing/20101022-00/?p=12473
]]

local fileExts <const> = { "ico" }
local visualTargets <const> = { "CANVAS", "LAYER", "SELECTION", "SLICES" }
local frameTargets <const> = { "ACTIVE", "ALL", "TAG" }

local defaults <const> = {
    visualTarget = "CANVAS",
    frameTarget = "ALL",
}

local dlg <const> = Dialog { title = "Ico Export" }

dlg:separator { id = "importSep" }

dlg:file {
    id = "importFilepath",
    label = "Open:",
    filetypes = fileExts,
    open = true,
    focus = true
}

dlg:newrow { always = false }

dlg:button {
    id = "importButton",
    text = "&IMPORT",
    focus = false,
    onclick = function()
        local args <const> = dlg.data
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
        if fileExtLc ~= "ico" then
            app.alert {
                title = "Error",
                text = "File extension must be ico."
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
        local ceil <const> = math.ceil
        local strbyte <const> = string.byte
        local strpack <const> = string.pack
        local strsub <const> = string.sub
        local strunpack <const> = string.unpack
        local tconcat <const> = table.concat

        local icoHeaderType <const> = strunpack("<I2", strsub(fileData, 3, 4))
        if icoHeaderType ~= 1 then
            app.alert {
                title = "Error",
                text = "Only icons are supported."
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

        -- TODO: wMax and hMax will become sprite width and height.
        local wMax = -2147483648
        local hMax = -2147483648
        local colorModeRgb <const> = ColorMode.RGB
        local colorSpacesRgb <const> = ColorSpace { sRGB = false }

        -- TODO: Not all ico entries may produce viable images, so cache them in an array first.
        ---@type Image[]
        local images <const> = {}

        local cursor = 6
        local h = 0
        while h < icoHeaderEntries do
            h = h + 1

            local icoWidth,
            icoHeight,
            numColors,
            reserved <const>,
            icoPlanes <const>,
            icoBpp <const>,
            dataSize <const>,
            dataOffset <const> = strunpack(
                "B B B B <I2 <I2 <I4 <I4",
                strsub(fileData, cursor + 1, cursor + 16))

            if icoWidth == 0 then icoWidth = 256 end
            if icoHeight == 0 then icoHeight = 256 end
            if numColors == 0 then numColors = 256 end

            print(h)
            print(string.format("icoWidth: %d, icoHeight: %d", icoWidth, icoHeight))
            print(string.format("numColors: %d", numColors))
            print(string.format("reserved: %d", reserved))
            print(string.format("icoPlanes: %d, icoBpp: %d", icoPlanes, icoBpp))
            print(string.format("dataSize: %d, dataOffset: %d", dataSize, dataOffset))

            -- TODO: Support recognition of compressed PNG headers instead of
            -- BMP headers, as they can be created by GIMP.
            local bmpHeaderSize <const>,
            bmpWidth <const>,
            bmpHeight2 <const>,
            bmpPlanes <const>,
            bmpBpp <const>,
            _ <const>,
            _ <const>,
            _ <const>,
            _ <const>,
            _ <const>,
            _ <const> = strunpack(
                "<I4 <I4 <I4 <I2 <I2 <I4 <I4 <I4 <I4 <I4 <I4",
                strsub(fileData, dataOffset + 1, dataOffset + 40))

            print(string.format("bmpHeaderSize: %d", bmpHeaderSize))
            print(string.format("bmpWidth: %d, bmpHeight2: %d", bmpWidth, bmpHeight2))
            print(string.format("bmpPlanes: %d, bmpBpp: %d", bmpPlanes, bmpBpp))

            local bmpHeight <const> = bmpHeight2 // 2
            if bmpWidth > wMax then wMax = bmpWidth end
            if bmpHeight > hMax then hMax = bmpHeight end
            local areaImage <const> = bmpWidth * bmpHeight
            local dWordsPerRow <const> = ceil(bmpWidth / 32)
            local lenDWords <const> = dWordsPerRow * bmpHeight

            print(string.format("dWordsPerRow: %d, lenDWords: %d", dWordsPerRow, lenDWords))

            local alphaMapOffset <const> = dataOffset + dataSize - lenDWords * 4

            ---@type integer[]
            local alphaMask <const> = {}
            local i = 0
            while i < areaImage do
                local x <const> = i % bmpWidth
                local y <const> = i // bmpWidth
                local xDWord <const> = x // 32
                local xBit <const> = 31 - x % 32
                local idxDWord <const> = 4 * (y * dWordsPerRow + xDWord)
                local dWord <const> = strunpack(">I4", strsub(fileData,
                    alphaMapOffset + 1 + idxDWord,
                    alphaMapOffset + 4 + idxDWord))
                local bit <const> = (dWord >> xBit) & 0x1
                alphaMask[1 + i] = bit
                i = i + 1
            end
            -- print(tconcat(alphaMask, ", "))

            ---@type string[]
            local byteStrs <const> = {}

            if bmpBpp == 8 then
                -- TODO: Do not allow for indexed color mode, even when bpp = 8 and
                -- numColors > 0. This is because you can't set a new palette per
                -- each frame like the Aseprite internal can. Maybe you'll have to
                -- track unique colors across all frames to set the palette, regardless
                -- of input bpp.

                ---@type integer[]
                local abgr32s <const> = {}
                local j = 0
                while j < numColors do
                    local j4 <const> = j * 4
                    -- local a8 <const> = 255
                    -- local a8 = strbyte(fileData, dataOffset + j4 + 40)
                    -- local b8 <const> = strbyte(fileData, dataOffset + j4 + 41)
                    -- local g8 <const> = strbyte(fileData, dataOffset + j4 + 42)
                    -- local r8 <const> = strbyte(fileData, dataOffset + j4 + 43)
                    local b8 <const>, g8 <const>, r8 <const> = strbyte(
                        fileData, dataOffset + j4 + 41, dataOffset + j4 + 43)
                    -- if j ~= 0 and r8 ~= 0 and g8 ~= 0 and b8 ~= 0 then
                    --     a8 = 255
                    -- end
                    -- print(string.format(
                    --     "r8: %03d, g8: %03d, b8: %03d, #%06X",
                    --     r8, g8, b8,
                    --     (r8 << 0x10 | g8 << 0x08 | b8)))

                    j = j + 1
                    local abgr32 <const> = 0xff000000 | b8 << 0x10 | g8 << 0x08 | r8
                    abgr32s[j] = abgr32
                end
            elseif bmpBpp == 24 then
                -- Wikipedia: "24 bit images are stored as B G R triples
                -- but are not DWORD aligned."
            elseif bmpBpp == 32 then
                -- Wikipedia: "32 bit images are stored as B G R A quads."
                -- local startColorMap <const> = dataOffset + 40

                local k = 0
                while k < areaImage do
                    local a8 = 0
                    local b8 = 0
                    local g8 = 0
                    local r8 = 0

                    local x <const> = k % bmpWidth
                    local yFlipped <const> = k // bmpWidth
                    local y <const> = bmpHeight - 1 - yFlipped

                    local bit <const> = alphaMask[1 + k]
                    if bit == 0 then
                        local k4 <const> = 4 * k
                        b8, g8, r8, a8 = strbyte(fileData,
                            dataOffset + k4 + 41,
                            dataOffset + k4 + 44)
                    end

                    -- print(string.format(
                    --     "x: %d, yFlipped: %d, y: %d, bit: %d\nr8: %03d, g8: %03d, b8: %03d, a8: %03d, #%06X",
                    --     x, yFlipped, y, bit, r8, g8, b8, a8,
                    --     (r8 << 0x10 | g8 << 0x08 | b8)))

                    local idxFlat <const> = y * bmpWidth + x
                    byteStrs[1 + idxFlat] = strpack("B B B B", r8, g8, b8, a8)

                    k = k + 1
                end
            end

            local imageSpec <const> = ImageSpec {
                width = bmpWidth,
                height = bmpHeight,
                colorMode = colorModeRgb,
                transparentColor = 0
            }
            imageSpec.colorSpace = colorSpacesRgb
            local image <const> = Image(imageSpec)
            image.bytes = tconcat(byteStrs)
            images[#images + 1] = image

            cursor = cursor + 16
            print(string.format("cursor: %d\n", cursor))
        end

        if wMax <= 0 or hMax <= 0 then
            app.alert {
                title = "Error",
                text = "The size of the new sprite is invalid."
            }
        end

        local spriteSpec <const> = ImageSpec {
            width = wMax,
            height = hMax,
            colorMode = colorModeRgb,
            transparentColor = 0
        }
        spriteSpec.colorSpace = colorSpacesRgb
        local sprite <const> = Sprite(spriteSpec)

        app.transaction("Set sprite file name.", function()
            sprite.filename = app.fs.fileName(importFilepath)
        end)

        local lenImages <const> = #images

        app.transaction("Create frames.", function()
            local m = 1
            while m < lenImages do
                m = m + 1
                sprite:newEmptyFrame()
            end
        end)

        local layer <const> = sprite.layers[1]
        local pointZero <const> = Point(0, 0)

        app.transaction("Create cels.", function()
            local n = 0
            while n < lenImages do
                n = n + 1
                local image <const> = images[n]
                sprite:newCel(layer, n, image, pointZero)
            end
        end)

        -- TODO: Assign a palette.
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
    filetypes = fileExts,
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
                text = "File extension must be ico."
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

            -- TODO: Would it be worth going through all frames in a preliminary
            -- loop and finding the minimum AABB around all images across frames
            -- then offseting image blit by that?
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

            local wBlit <const> = min(256, wBounds)
            local hBlit <const> = min(256, hBounds)
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
            local slicesSprite <const> = activeSprite.slices
            local lenSlicesSprite <const> = #slicesSprite
            if lenSlicesSprite <= 0 then
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
            while h < lenSlicesSprite do
                h = h + 1
                local slice <const> = slicesSprite[h]
                local boundsSlice <const> = slice.bounds or defaultBounds
                local xtlBounds <const> = boundsSlice.x
                local ytlBounds <const> = boundsSlice.y
                local wBounds <const> = max(1, abs(boundsSlice.width))
                local hBounds <const> = max(1, abs(boundsSlice.height))
                local blitOffset <const> = Point(-xtlBounds, -ytlBounds)

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

        -- Threshold for alpha at or below which mask is set to ignore.
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
                0,         -- 1 bytes, color count, 0 if gt 256
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
                        if a8 > 0 then
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
    focus = false,
    onclick = function()
        dlg:close()
    end
}

dlg:show { wait = false }