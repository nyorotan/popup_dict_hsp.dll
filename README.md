🌐 **English** | [日本語](./README.ja.md)

# popup_dict_hsp.dll

A module that adds dictionary pop-up functionality to the HSP3 `webview2_hsp.dll`. When you hover over text in WebView2, it looks up the word and displays the result in a borderless HSP3 window.

This repository consists of the HSP3 module `popup_dict.as`, the dictionary search DLL `Jmdict/popup_dict_hsp.dll`, and the JavaScript `Jmdict/dict_injector.js`, which sends events from WebView2. `popup_dict_hsp.dll` is an add-on module separate from the WebView2 host DLL, `webview2_hsp.dll`.

## Features

- Look up words selected or hovered over in WebView2
- Display results in a pop-up window that follows the mouse pointer
- Enable, disable, or hide the pop-up
- Load a dictionary from a CSV file or use the dictionary data embedded in the DLL

## Requirements

- Windows
- HSP 3.6 or later
- Microsoft Edge WebView2 Runtime
- `webview2_hsp.dll` and `Jmdict/popup_dict_hsp.dll` matching the bitness of the HSP3 runtime

The standard `build.bat` builds a 32-bit `Jmdict/popup_dict_hsp.dll`. To use a 64-bit version, use a DLL built with a 64-bit compiler.

## Files

- `webview2_hsp.dll` — DLL that provides the WebView2 control
- `hsp3webview2.as` — HSP3 module that calls the WebView2 DLL
- `popup_dict.as` — HSP3 module that connects dictionary lookup and pop-up display to WebView2
- `Jmdict/popup_dict_hsp.dll` — DLL that loads and searches dictionary data
- `Jmdict/dict_injector.js` — Script that detects words in WebView2 and notifies HSP3
- `Jmdict/jmdict_simple.csv` — External dictionary CSV (the DLL's embedded dictionary data is used if omitted)
- `sample_dict.hsp` — Usage example
- `build.bat` — Dictionary DLL build script

## Usage

Include `hsp3webview2.as` and `popup_dict.as`, then call `dict_attach_webview` after creating the WebView2 control.

```hsp
#include "hsp3webview2.as"
#include "popup_dict.as"

#define WM_USER_WV2_MSG 0x8001

    wv2_create id_wv, hwnd, 0, 0, 800, 600, 1
    if id_wv == 0 {
        dialog "Failed to create WebView2.", 1, "Error"
        end
    }

    dict_attach_webview id_wv, hwnd, WM_USER_WV2_MSG, 1, "", "Jmdict/dict_injector.js"
    dict_enable
```

The arguments to `dict_attach_webview` are, in order: the WebView2 ID, the HWND of the window receiving notifications, the notification message ID, the pop-up window ID, the dictionary CSV path, and the JavaScript path. Pass an empty string for the dictionary CSV path to use the dictionary data embedded in the DLL. Specify relative paths from the HSP3 runtime folder.

Call `dict_disable` to disable dictionary pop-ups, `dict_enable` to enable them again, and `dict_hide_popup` to hide the pop-up. On exit, destroy WebView2 by calling `wv2_destroy`.

## Build

You need Go and a 32-bit MinGW-w64 GCC installation with cgo support. Run `build.bat` from the repository root to generate `Jmdict/popup_dict_hsp.dll`.

```cmd
build.bat
```

## Creating dictionary data

This software uses JMdict for its dictionary. `Jmdict/convert.py` reads JMdict XML and creates `jmdict_simple.csv` for searching. The raw `JMdict_e.gz` file is not included in this repository, so download it separately. The conversion script requires only the Python 3 standard library.

```cmd
cd Jmdict
curl.exe -L -o JMdict_e.gz http://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz
python -c "import gzip, shutil; shutil.copyfileobj(gzip.open('JMdict_e.gz', 'rb'), open('JMdict_e', 'wb'))"
python convert.py
cd ..
```

Download source: [JMdict_e.gz](http://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz)

The generated `Jmdict/jmdict_simple.csv` is saved as UTF-8 with a BOM. To update the dictionary embedded in the DLL, run `build.bat` from the repository root to rebuild the DLL. To use the CSV as an external file, specify `Jmdict/jmdict_simple.csv` as the dictionary CSV path in `dict_attach_webview`.

## License

This project is released under the [MIT License](./LICENSE) and may be used freely for commercial and non-commercial purposes. See `CREDITS` for the licenses and sources of the dictionary data.

- **Copyright**: © 2026 nyorotan

## Version

- **Version**: v1.0.0
- **Author**: nyorotan
