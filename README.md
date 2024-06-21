# Aseprite Ico Export

![Screen Capture](screenCap.png)

This an [Aseprite](https://www.aseprite.org/) script to export `ico`s in 32-bit RGBA format, i.e., with translucency. Aseprite is an "animated sprite editor and pixel art tool."

Aseprite supports `ico`s, but the built-in feature does not include the alpha channel. This export is limited to to the size 256 by 256 pixels. It will write a file as 32-bit RGBA regardless of the sprite's color mode (grayscale, indexed or RGB). Each frame is stored as a separate entry in the same `ico` file. To read more about the format, see the [Wikipedia](https://en.wikipedia.org/wiki/ICO_(file_format)) entry.

*This script was developed and tested in Aseprite version 1.3.7 on Windows 10.*

## Download

To download this script, click on the green Code button above, then select Download Zip. You can also click on the `icoio.lua` file. Beware that some browsers will append a `.txt` file format extension to script files on download. Aseprite will not recognize the script until this is removed and the original `.lua` extension is used. There can also be issues with copying and pasting. Be sure to click on the Raw file button. Do not copy the formatted code.

## Installation

To install this script, open Aseprite. In the menu bar, go to `File > Scripts > Open Scripts Folder`. Move the Lua script(s) into the folder that opens. Return to Aseprite; go to `File > Scripts > Rescan Scripts Folder`. The script should now be listed under `File > Scripts`. Select `icoio.lua` to launch the dialog.

If an error message in Aseprite's console appears, check if the script folder is on a file path that includes characters beyond ASCII, such as 'é' (e acute) or 'ö' (o umlaut).

## Usage

A hot key can be assigned to a script by going to `Edit > Keyboard Shortcuts`. The search input box in the top left of the shortcuts dialog can be used to locate the script by its file name.

Once open, holding down the `Alt` or `Option` key and pressing the underlined letter on a button will activate that button via keypress. For example, `Alt+C` will cancel the dialog.

## Modification

If you would like to modify this script, Aseprite's scripting API documentation can be found [here](https://aseprite.org/api/). If you use [Visual Studio Code](https://code.visualstudio.com/), I recommend the [Lua Language Server](https://github.com/LuaLS/lua-language-server) extension along with an [Aseprite type definition](https://github.com/behreajj/aseprite-type-definition).