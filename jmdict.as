// ==============================================================================
// Jmdic モジュール (jmdic.as)
// ==============================================================================
// 文字コード: Shift-JIS
// ==============================================================================
#ifndef __JMDIC_AS__
#define __JMDIC_AS__


#uselib "Jmdict/jmdict.dll"
#func global _jmdic_load      "jmdic_load"      sptr
#func global _jmdic_is_loaded "jmdic_is_loaded"
#func global _jmdic_search    "jmdic_search"    sptr, int, int, int, int
#func global _jmdic_free      "jmdic_free"
#uselib "user32.dll"
#func global _SetWindowPos "SetWindowPos" sptr, sptr, sptr, sptr, sptr, sptr, sptr
#func global _GetWindowRect "GetWindowRect" sptr, var
#module mod_jmdic

// 辞書機能の有効/無効フラグ
#define global DICT_ENABLED  1
#define global DICT_DISABLED 0

//有効/無効フラグ
#deffunc dict_enable
    dict_enabled_flag = DICT_ENABLED
    return

#deffunc dict_disable
    dict_enabled_flag = DICT_DISABLED
    dict_hide_popup
    return

#defcfunc dict_is_enabled
    return dict_enabled_flag

// ------------------------------------------------------------------------------
// 辞書CSVの読み込み
//   p_path : CSVファイルパス (省略時: "Jmdict/jmdict_simple.csv")
//   戻り値 : stat > 0 (読み込んだ語数), stat <= 0 (エラー)
// ------------------------------------------------------------------------------
#deffunc dict_init str p_path
    csv_file = p_path
    if csv_file == "" {
        csv_file = "Jmdict/jmdict_simple.csv"
        exist csv_file
        if strsize == -1 {
            csv_file = "Jmdict/jmdict_simple.csv"
        }
    }
    _jmdic_load csv_file
    return stat

// ------------------------------------------------------------------------------
// 読み込み済みか確認
//   戻り値 : 1 (ロード済), 0 (未ロード)
// ------------------------------------------------------------------------------
#defcfunc dict_is_ready
    _jmdic_is_loaded
    return stat

// ------------------------------------------------------------------------------
// 単語検索（直接呼び出し用）
//   v_out   : 結果受け取り文字列変数 (タブ・改行区切り)
//   p_word  : 単語
//   p_exact : 1 = 完全一致, 0 = 前方一致 (デフォルト: 0)
//   p_limit : 最大件数 (デフォルト: 5)
//   戻り値  : stat > 0 (取得バイト数 / 該当あり), stat == 0 (該当なし)
// ------------------------------------------------------------------------------
#deffunc dict_lookup var v_out, str p_word, int p_exact, int p_limit
    word = p_word
    exact = p_exact
    alimit = p_limit
    if alimit <= 0 : alimit = 5

    max_len = 16384
    sdim v_out, max_len

    _jmdic_search word, exact, alimit, varptr(v_out), max_len
    return stat

// ------------------------------------------------------------------------------
// 最長一致検索
//   v_out    : 結果受け取り文字列変数
//   p_phrase : 探索対象の文字列（語頭から最長一致を探す）
//   p_limit  : 最大件数 (デフォルト: 3)
//   戻り値   : stat > 0 (該当あり), stat == 0 (該当なし)
// ------------------------------------------------------------------------------
#deffunc dict_lookup_longest var v_out, str p_phrase, int p_limit
    dict_lookup_longest_min v_out, p_phrase, 0, p_limit
    return stat

#deffunc dict_lookup_longest_min var v_out, str p_phrase, int p_min_bytes, int p_limit
    alimit = p_limit
    if alimit <= 0 : alimit = 3

    sdim v_out, 16384
    sdim cur_word, 256
    cur_word = p_phrase
    found = 0
    single_hiragana = 0
    phrase_len = strlen(cur_word)
    if phrase_len == 2 {
        first_byte = peek(cur_word, 0)
        second_byte = peek(cur_word, 1)
        if first_byte == 0x82 && second_byte >= 0x9f && second_byte <= 0xf1 : single_hiragana = 1
    }

    repeat
        if cur_word == "" : break

        wlen = strlen(cur_word)
        if wlen == 2 {
            first_byte = peek(cur_word, 0)
            second_byte = peek(cur_word, 1)
            if first_byte == 0x82 && second_byte >= 0x9f && second_byte <= 0xf1 {
                cur_word = ""
                break
            }
        }

        dict_lookup v_out, cur_word, 1, alimit
        if stat > 0 {
            found = 1
            break
        }
        if wlen <= p_min_bytes {
            cur_word = ""
            break
        }

        // Shift-JISの文字境界を考慮して末尾の1文字を削る
        if wlen <= 1 {
            cur_word = ""
            break
        }

        last_pos = 0
        scan_pos = 0
        repeat
            if scan_pos >= wlen : break
            last_pos = scan_pos
            c = peek(cur_word, scan_pos)
            if (c >= 0x81 && c <= 0x9f) || (c >= 0xe0 && c <= 0xfc) {
                scan_pos += 2
            } else {
                scan_pos += 1
            }
        loop

        if last_pos <= 0 {
            cur_word = ""
            break
        }
        cur_word = strmid(cur_word, 0, last_pos)
    loop

    // 見つからなかった場合は元の切り出し文字列で前方一致
    if found == 0 && single_hiragana == 0 {
        dict_lookup v_out, p_phrase, 0, alimit
        if stat > 0 : found = 1
    }

    return found

#deffunc dict_lookup_around var v_out, str p_word, str p_left_near_first, int p_limit
    if p_word == "" : return 0

    sdim left_source, 256
    sdim left_part, 256
    sdim candidate, 512
    sdim target_source, 256
    left_source = p_left_near_first
    target_source = p_word
    left_part = ""
    left_pos = 0
    left_len = strlen(left_source)

    repeat
        if left_pos >= left_len : break

        char_len = 1
        c = peek(left_source, left_pos)
        if (c >= 0x81 && c <= 0x9f) || (c >= 0xe0 && c <= 0xfc) {
            char_len = 2
        }
        left_part = strmid(left_source, left_pos, char_len) + left_part
        candidate = left_part + p_word
        min_bytes = strlen(left_part) + 1
        first_target_byte = peek(target_source, 0)
        if (first_target_byte >= 0x81 && first_target_byte <= 0x9f) || (first_target_byte >= 0xe0 && first_target_byte <= 0xfc) {
            min_bytes += 1
        }

        dict_lookup_longest_min v_out, candidate, min_bytes, p_limit
        if stat > 0 : return 1

        left_pos += char_len
    loop

    dict_lookup_longest v_out, p_word, p_limit
    return stat

// ------------------------------------------------------------------------------
// WebView2 連携ポップアップ辞書の初期化＆バインド
//   p_wv_id     : WebView2のID (wv2_createで取得したID)
//   p_parent_hwnd: 通知を受け取るメインウィンドウのHWND (hwnd)
//   p_msg_id    : 通知用WindowsメッセージID (省略時: 0x8001)
//   p_pop_id    : ポップアップウィンドウのウィンドウID (省略時: 1)
//   p_csv_path  : 辞書CSVパス (省略時: "Jmdic/jmdict_simple.csv")
//   p_js_path   : JSインジェクタパス (省略時: "dict_injector.js")
// ------------------------------------------------------------------------------
#deffunc dict_attach_webview int p_wv_id, int p_parent_hwnd, int p_msg_id, int p_pop_id, str p_csv_path, str p_js_path
    wv_id = p_wv_id
    parent_hwnd = p_parent_hwnd
    msg_id = p_msg_id
    if msg_id == 0 : msg_id = 0x8001
    pop_id = p_pop_id
    if pop_id <= 0 : pop_id = 1

    pop_w = 380
    pop_h = 200

    // 辞書ロード
    dict_init p_csv_path

    // JSインジェクションスクリプト読み込み＆登録
    js_file = p_js_path
    if js_file == "" : js_file = "dict_injector.js"
    exist js_file
    if strsize != -1 {
        notesel js_code
        noteload js_file
        wv2_add_init_script wv_id, js_code
    }

    // メッセージ通知設定
    wv2_set_notify wv_id, parent_hwnd, msg_id

    // ポップアップ用 枠なしウィンドウの作成
    old_sel = ginfo_sel
    bgscr pop_id, pop_w, pop_h, 2, 0, 0
    gsel pop_id, 2
    pop_hwnd = hwnd
    sdim popup_text, 32768
    font "msgothic", 16, 17
    objmode 2, 1
    pos 8, 8
    mesbox popup_text, 364, 184, 0
    popup_text_obj = stat
    gsel pop_id, -1
    gsel old_sel

    // メッセージハンドラ登録
    oncmd gosub *on_wv2_dict_message, msg_id
    dict_active_state = DICT_ENABLED
    return

// ------------------------------------------------------------------------------
// ポップアップの表示・非表示制御
// ------------------------------------------------------------------------------
#deffunc dict_hide_popup
    if pop_id == 1 {
        gsel pop_id, -1
    }
    return

// ------------------------------------------------------------------------------
// 内部メッセージハンドラ（Webからの通知を受信して辞書検索・描画）
// ------------------------------------------------------------------------------
*on_wv2_dict_message
    // 無効なら何もしない
    if dict_is_enabled() == DICT_DISABLED : return
    sdim recv_buf, 4096
    wv2_get_message wv_id, recv_buf, 4096
    if recv_buf == "" : return

    if recv_buf == "DICT_HIDE" {
        // マウスがポップアップ内にあるか判定
        dim rect, 4
        _GetWindowRect pop_hwnd, rect // rect(0):左, rect(1):上, rect(2):右, rect(3):下
        if (ginfo_mx >= rect(0) && ginfo_mx <= rect(2) && ginfo_my >= rect(1) && ginfo_my <= rect(3)) {
            return // マウスがポップアップウィンドウの矩形内にある
        }
        dict_hide_popup
        return    }

    screen_x = ginfo_mx
    screen_y = ginfo_my

    sdim remain, 4096
    sdim left_context, 256
    if instr(recv_buf, 0, "DICT2:") == 0 {
        remain = strmid(recv_buf, 6, strlen(recv_buf) - 6)

        p1 = instr(remain, 0, ":")
        if p1 == -1 : return
        target_word = strmid(remain, 0, p1)

        p2 = instr(remain, p1 + 1, ":")
        if p2 == -1 : return
        left_context = strmid(remain, p1 + 1, p2 - p1 - 1)

        p3 = instr(remain, p2 + 1, ":")
        if p3 == -1 : return
    } else {
        if instr(recv_buf, 0, "DICT:") != 0 : return
        remain = strmid(recv_buf, 5, strlen(recv_buf) - 5)

        p1 = instr(remain, 0, ":")
        if p1 == -1 : return
        target_word = strmid(remain, 0, p1)

        p2 = instr(remain, p1 + 1, ":")
        if p2 == -1 : return
        left_context = ""
    }

    sdim dict_result, 16384
    dict_lookup_around dict_result, target_word, left_context, 3

    if stat > 0 {
        // スクリーン座標基準のポップアップ配置
        popup_x = screen_x
        popup_y = screen_y

        if popup_x + pop_w > ginfo_dispx {
            popup_x = screen_x - pop_w
        }
        if popup_y + pop_h > ginfo_dispy {
            popup_y = screen_y - pop_h
        }

        if popup_x < 8 : popup_x = 8
        if popup_y < 8 : popup_y = 8

        old_sel = ginfo_sel
        gsel pop_id
        width pop_w, pop_h
        _SetWindowPos pop_hwnd, 0, popup_x, popup_y, pop_w, pop_h, 0x0050

        // 背景・枠描画（ダークモダン）
        color 30, 33, 36 : boxf 0, 0, pop_w, pop_h
        color 80, 85, 90
        line 0, 0, pop_w - 1, 0
        line pop_w - 1, 0, pop_w - 1, pop_h - 1
        line pop_w - 1, pop_h - 1, 0, pop_h - 1
        line 0, pop_h - 1, 0, 0

        popup_text = ""
        notesel dict_result
        repeat notemax
            noteget line_str, cnt
            if line_str == "" : continue

            t1 = instr(line_str, 0, "\t")
            if t1 == -1 : continue
            d_kanji = strmid(line_str, 0, t1)

            t2 = instr(line_str, t1 + 1, "\t")
            if t2 == -1 : continue
            d_kana = strmid(line_str, t1 + 1, t2)
            d_gloss = strmid(line_str, t1 + 1 + t2 + 1, strlen(line_str))
            popup_text += d_kanji + " [" + d_kana + "]\n" + d_gloss + "\n\n"
        loop
        objprm popup_text_obj, popup_text

        gsel pop_id, 1
        gsel old_sel
    } else {
        dict_hide_popup
    }
    return

// ------------------------------------------------------------------------------
// 解放
// ------------------------------------------------------------------------------
#deffunc dict_cleanup onexit
    // dict_hide_popup
    _jmdic_free
    return

#global

#endif // __JMDIC_AS__
