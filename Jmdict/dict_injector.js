(function() {
    console.log("[dict_injector] loaded");

    let hoverTimer = null;
    let lastWord = "";

    // rt, rpタグ（ルビ本体・括弧）およびその中身をスキップして、テキストノードを辿るヘルパー
    function getNextCharInDOM(textNode, offset) {
        let node = textNode;
        let off = offset;

        while (node) {
            if (node.nodeType === Node.TEXT_NODE) {
                // 親や祖先に rt または rp がある場合はルビ読み仮名なのでスキップ
                let p = node.parentElement;
                let isRubyText = false;
                while (p && p !== document.body) {
                    const tag = p.tagName ? p.tagName.toUpperCase() : "";
                    if (tag === "RT" || tag === "RP") {
                        isRubyText = true;
                        break;
                    }
                    p = p.parentElement;
                }

                if (!isRubyText) {
                    const text = node.textContent;
                    if (off < text.length) {
                        return { char: text[off], nextNode: node, nextOffset: off + 1 };
                    }
                }
            }

            // 次のノードへ進む（深さ優先走査）
            off = 0;
            if (node.firstChild) {
                node = node.firstChild;
            } else if (node.nextSibling) {
                node = node.nextSibling;
            } else {
                let parent = node.parentNode;
                while (parent && parent !== document.body && !parent.nextSibling) {
                    parent = parent.parentNode;
                }
                node = parent && parent !== document.body ? parent.nextSibling : null;
            }
        }
        return null;
    }

    function getPreviousCharInDOM(textNode, offset) {
        let node = textNode;
        let off = offset;

        while (node) {
            if (node === document.body) break;

            if (node.nodeType === Node.TEXT_NODE) {
                let p = node.parentElement;
                let isRubyText = false;
                while (p && p !== document.body) {
                    const tag = p.tagName ? p.tagName.toUpperCase() : "";
                    if (tag === "RT" || tag === "RP") {
                        isRubyText = true;
                        break;
                    }
                    p = p.parentElement;
                }

                if (!isRubyText && off > 0) {
                    return { char: node.textContent[off - 1], prevNode: node, prevOffset: off - 1 };
                }
            }

            if (node.previousSibling) {
                node = node.previousSibling;
                while (node.lastChild) {
                    node = node.lastChild;
                }
                off = node.nodeType === Node.TEXT_NODE ? node.textContent.length : 0;
            } else {
                node = node.parentNode;
                off = 0;
            }
        }
        return null;
    }

    function getCharOffsetAtPoint(textNode, offset, x, y) {
        const text = textNode.textContent;
        const candidates = [offset - 1, offset].filter(index => index >= 0 && index < text.length);
        let closestOffset = offset;
        let closestDistance = Infinity;

        for (const index of candidates) {
            const range = document.createRange();
            range.setStart(textNode, index);
            range.setEnd(textNode, index + 1);
            const rect = range.getBoundingClientRect();
            if (rect.width === 0 && rect.height === 0) continue;

            const dx = x < rect.left ? rect.left - x : x > rect.right ? x - rect.right : 0;
            const dy = y < rect.top ? rect.top - y : y > rect.bottom ? y - rect.bottom : 0;
            const distance = dx * dx + dy * dy;
            if (distance < closestDistance) {
                closestDistance = distance;
                closestOffset = index;
            }
        }

        return closestOffset;
    }

    // 単語抽出
    function getWordAtPoint(x, y) {
        let range;
        if (document.caretRangeFromPoint) {
            range = document.caretRangeFromPoint(x, y);
        } else if (document.caretPositionFromPoint) {
            const pos = document.caretPositionFromPoint(x, y);
            if (pos) {
                range = document.createRange();
                range.setStart(pos.offsetNode, pos.offset);
                range.collapse(true);
            }
        }

        if (range && range.startContainer && range.startContainer.nodeType === Node.TEXT_NODE) {
            const textNode = range.startContainer;
            const fullText = textNode.textContent;
            const offset = range.startOffset;

            // もしカーソルがルビ(rt / rp)の中にある場合は、親ruby要素または次のベース文字を起点にする
            let currentParent = textNode.parentElement;
            let insideRubyRt = false;
            while (currentParent && currentParent !== document.body) {
                const tag = currentParent.tagName ? currentParent.tagName.toUpperCase() : "";
                if (tag === "RT" || tag === "RP") {
                    insideRubyRt = true;
                    break;
                }
                currentParent = currentParent.parentElement;
            }

            let startNode = textNode;
            let startOffset = getCharOffsetAtPoint(textNode, offset, x, y);
            if (insideRubyRt && currentParent && currentParent.parentElement) {
                // ルビタグ自体ではなく、対応するruby要素全体または次の兄弟ノードを対象に
                startNode = currentParent.parentElement;
                startOffset = 0;
            }

            if (startOffset < (startNode.textContent ? startNode.textContent.length : 0) || startNode.nodeType !== Node.TEXT_NODE) {
                const isWordChar = (ch) => /[\p{L}\p{N}_々ヶー]/u.test(ch);
                const isAsciiWordChar = (ch) => /[a-zA-Z0-9_]/.test(ch);
                const isKatakana = (ch) => /[\u30A0-\u30FFー]/.test(ch);
                const currentCh = startNode.nodeType === Node.TEXT_NODE
                    ? startNode.textContent[startOffset] || ""
                    : "";
                const preceding = [];
                if (!insideRubyRt) {
                    let prevNode = startNode;
                    let prevOffset = startOffset;
                    while (preceding.length < 15) {
                        const prev = getPreviousCharInDOM(prevNode, prevOffset);
                        if (!prev || !isWordChar(prev.char)) break;
                        preceding.push(prev.char);
                        prevNode = prev.prevNode;
                        prevOffset = prev.prevOffset;
                    }
                }

                let collected = "";
                let cur = { char: "", nextNode: startNode, nextOffset: startOffset };
                let followingLength = 0;
                const rightLimit = isAsciiWordChar(currentCh) ? 40 : isKatakana(currentCh) ? 20 : 15;
                while (followingLength < rightLimit) {
                    cur = getNextCharInDOM(cur.nextNode, cur.nextOffset);
                    if (!cur) break;
                    if (!isWordChar(cur.char)) {
                        break; // 句読点、空白、記号などに到達したら終了
                    }
                    collected += cur.char;
                    followingLength++;
                }

                if (collected.length > 0) {
                    return { word: collected.trim(), left: preceding.join("") };
                }
            }
        }

        const elem = document.elementFromPoint(x, y);
        if (elem) {
            // ルビタグとその中身を除去したクローンからテキストを取得
            const clone = elem.cloneNode(true);
            const rubies = clone.querySelectorAll("rt, rp");
            rubies.forEach(el => el.remove());
            const txt = (clone.innerText || clone.textContent || "").trim();
            if (txt.length > 0 && txt.length <= 15) {
                return { word: txt, left: "" };
            }
        }

        return null;
    }

    function postDictionaryRequest(candidate, e) {
        if (candidate && window.chrome && window.chrome.webview) {
            window.chrome.webview.postMessage(
                "DICT2:" + candidate.word + ":" + candidate.left + ":" +
                Math.round(e.screenX) + ":" + Math.round(e.screenY)
            );
        }
    }

    // マウスホバー監視 (スクリーン座標 e.screenX, e.screenY を送信)
    document.addEventListener("mousemove", function(e) {
        clearTimeout(hoverTimer);
        hoverTimer = setTimeout(() => {
            const candidate = getWordAtPoint(e.clientX, e.clientY);

            // 単語からマウスが外れても、すぐに消さずに猶予を持たせる（コピー操作などをしやすくする）
            if (!candidate) {
                if (!window._hideTimer) {
                    window._hideTimer = setTimeout(() => {
                        lastWord = "";
                        if (window.chrome && window.chrome.webview) {
                            window.chrome.webview.postMessage("DICT_HIDE");
                        }
                        window._hideTimer = null;
                    }, 1000);
                }
                return;
            }

            if (window._hideTimer) {
                clearTimeout(window._hideTimer);
                window._hideTimer = null;
            }

            const currentKey = candidate ? candidate.word + "\0" + candidate.left : "";
            if (candidate && currentKey !== lastWord) {
                lastWord = currentKey;
                postDictionaryRequest(candidate, e);
            }
        }, 150);
    });

    // クリック時
    document.addEventListener("click", function(e) {
        postDictionaryRequest(getWordAtPoint(e.clientX, e.clientY), e);
    });

    document.addEventListener("scroll", function() {
        lastWord = "";
        if (window.chrome && window.chrome.webview) {
            window.chrome.webview.postMessage("DICT_HIDE");
        }
    }, true);
})();
