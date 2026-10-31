🌐 [English](./README.md) | **日本語**

# popup_dict_hsp.dll

HSP3 の `webview2_hsp.dll` に辞書ポップアップ機能を追加するモジュールです。WebView2 上の文章にマウスを合わせると単語を検索し、結果を HSP3 の枠なしウィンドウに表示します。

このリポジトリでは、ポップアップ機能を HSP3 モジュール `popup_dict.as`、辞書検索 DLL `Jmdict/popup_dict_hsp.dll`、WebView2 にイベントを送る JavaScript `Jmdict/dict_injector.js` で構成しています。`popup_dict_hsp.dll` は WebView2 本体の `webview2_hsp.dll` とは別の追加モジュールとして使用します。

## 主な機能

- WebView2 上で選択・ホバーされた単語を辞書検索
- 検索結果をマウス位置に追従するポップアップウィンドウに表示
- ポップアップの有効化、無効化、非表示
- 辞書 CSV を指定して読み込み、または DLL に埋め込まれた辞書データを使用

## 動作要件

- Windows
- HSP 3.6 以降
- Microsoft Edge WebView2 Runtime
- HSP3 ランタイムとビット数が一致する `webview2_hsp.dll` と `Jmdict/popup_dict_hsp.dll`

標準の `build.bat` は 32 bit 版の `Jmdict/popup_dict_hsp.dll` をビルドします。64 bit 版を使用する場合は、64 bit 用のコンパイラーでビルドした DLL を使用してください。

## ファイル

- `webview2_hsp.dll` — WebView2 コントロールを提供する DLL
- `hsp3webview2.as` — WebView2 DLL を呼び出す HSP3 モジュール
- `jmdict.as` — 辞書検索とポップアップ表示を WebView2 に結び付ける HSP3 モジュール
- `Jmdict/popup_dict_hsp.dll` — 辞書データの読み込みと検索を行う DLL
- `Jmdict/dict_injector.js` — WebView2 上の単語検出と HSP3 への通知を行うスクリプト
- `Jmdict/jmdict_simple.csv` — 外部辞書 CSV（省略時は DLL 内の辞書データを使用）
- `sample_dict.hsp` — 使用例
- `build.bat` — 辞書 DLL のビルドスクリプト

## 使い方

`hsp3webview2.as` と `jmdict.as` をインクルードし、WebView2 を作成した後に `dict_attach_webview` を呼び出します。

```hsp
#include "hsp3webview2.as"
#include "jmdict.as"

#define WM_USER_WV2_MSG 0x8001

    wv2_create id_wv, hwnd, 0, 0, 800, 600, 1
    if id_wv == 0 {
        dialog "WebView2 の作成に失敗しました。", 1, "エラー"
        end
    }

    dict_attach_webview id_wv, hwnd, WM_USER_WV2_MSG, 1, "", "Jmdict/dict_injector.js"
    dict_enable
```

`dict_attach_webview` の引数は、WebView2 の ID、通知を受け取るウィンドウの HWND、通知メッセージ ID、ポップアップウィンドウ ID、辞書 CSV のパス、JavaScript のパスの順です。辞書 CSV のパスを空文字列にすると DLL 内の辞書データを使用します。相対パスは HSP3 の実行時フォルダーを基準に指定してください。

辞書ポップアップを無効にする場合は `dict_disable`、再び有効にする場合は `dict_enable`、非表示にする場合は `dict_hide_popup` を呼び出します。終了時には WebView2 を `wv2_destroy` で破棄してください。

## ビルド

Go と cgo 対応の 32 bit MinGW-w64 GCC が必要です。リポジトリのルートで `build.bat` を実行すると、`Jmdict/popup_dict_hsp.dll` が生成されます。

```cmd
build.bat
```

## 辞書データの作成

このソフトウェアの辞書には JMdict を使用しています。`Jmdict/convert.py` は JMdict の XML を読み込み、検索用の `jmdict_simple.csv` を作成します。未加工の `JMdict_e.gz` はリポジトリに含まれていないため、別途ダウンロードしてください。Python 3 の標準ライブラリのみで変換できます。

```cmd
cd Jmdict
curl.exe -L -o JMdict_e.gz http://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz
python -c "import gzip, shutil; shutil.copyfileobj(gzip.open('JMdict_e.gz', 'rb'), open('JMdict_e', 'wb'))"
python convert.py
cd ..
```

ダウンロード元: [JMdict_e.gz](http://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz)

変換後の `Jmdict/jmdict_simple.csv` は UTF-8（BOM付き）で保存されます。DLL 内蔵の辞書を更新するには、リポジトリのルートで `build.bat` を実行し、DLL を再ビルドしてください。CSV を外部ファイルとして使う場合は、`dict_attach_webview` の辞書 CSV パスに `Jmdict/jmdict_simple.csv` を指定します。

## ライセンス

本プロジェクトは`MITライセンス`の元で公開されています。商用・非商用問わず自由にご利用ください。
辞書データのライセンスおよび出典については `CREDITS` を参照してください。

- **著作権**: © 2026 nyorotan

## バージョン情報

- **バージョン**: v1.0.0
- **作者**: nyorotan
