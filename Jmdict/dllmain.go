package main

/*
#include <stdlib.h>
#include <string.h>
*/
import "C"
import (
	"bytes"
	"encoding/csv"
	"fmt"
	"io"
	"os"
	"sort"
	"strings"
	"sync"
	"unicode/utf8"
	"unsafe"

	"golang.org/x/text/encoding/japanese"
	"golang.org/x/text/transform"
)

// Entry は辞書の1項目を表す構造体
type Entry struct {
	Kanji   string
	Kana    string
	Glosses string
}

// Dictionary は辞書データを保持する構造体
type Dictionary struct {
	Entries []Entry
}

var (
	globalDict *Dictionary
	dictMu     sync.RWMutex
)

// Shift-JIS と UTF-8 の相互変換ユーティリティ
func toUTF8(b []byte) string {
	if utf8.Valid(b) {
		return string(b)
	}
	r := transform.NewReader(bytes.NewReader(b), japanese.ShiftJIS.NewDecoder())
	d, err := io.ReadAll(r)
	if err != nil {
		return string(b)
	}
	return string(d)
}

func cString(cstr *C.char) string {
	if cstr == nil {
		return ""
	}
	b := C.GoBytes(unsafe.Pointer(cstr), C.int(C.strlen(cstr)))
	return strings.TrimSpace(toUTF8(b))
}

func copyToCBuf(src string, outBuf *C.char, maxLen C.int) C.int {
	if outBuf == nil || maxLen <= 0 {
		return 0
	}
	sjisBytes := toShiftJIS(src)
	copyLen := len(sjisBytes)
	limit := int(maxLen) - 1
	if copyLen > limit {
		copyLen = limit
	}

	for i := 0; i < copyLen; {
		if (sjisBytes[i] >= 0x81 && sjisBytes[i] <= 0x9f) || (sjisBytes[i] >= 0xe0 && sjisBytes[i] <= 0xfc) {
			if i+1 >= copyLen {
				copyLen = i
				break
			}
			i += 2
		} else {
			i++
		}
	}

	ptr := (*[1 << 30]byte)(unsafe.Pointer(outBuf))
	copy(ptr[:copyLen], sjisBytes[:copyLen])
	ptr[copyLen] = 0 // NULL終端

	return C.int(copyLen)
}

//export jmdict_load
func jmdict_load(csvPath *C.char) C.int {
	path := cString(csvPath)
	if path == "" {
		path = "jmdict_simple.csv"
	}

	file, err := os.Open(path)
	if err != nil {
		return -1
	}
	defer file.Close()

	reader := csv.NewReader(file)
	// ヘッダー読み飛ばし
	_, err = reader.Read()
	if err != nil {
		return -2
	}

	var entries []Entry
	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			continue
		}
		if len(record) >= 3 {
			entries = append(entries, Entry{
				Kanji:   record[0],
				Kana:    record[1],
				Glosses: strings.ReplaceAll(record[2], " || ", " / "),
			})
		}
	}

	dictMu.Lock()
	globalDict = &Dictionary{Entries: entries}
	count := len(entries)
	dictMu.Unlock()

	return C.int(count)
}

//export jmdict_is_loaded
func jmdict_is_loaded() C.int {
	dictMu.RLock()
	defer dictMu.RUnlock()
	if globalDict != nil && len(globalDict.Entries) > 0 {
		return 1
	}
	return 0
}

//export jmdict_search
func jmdict_search(cKeyword *C.char, exact C.int, limit C.int, outBuf *C.char, maxLen C.int) C.int {
	dictMu.RLock()
	dict := globalDict
	dictMu.RUnlock()

	if dict == nil || len(dict.Entries) == 0 {
		return 0
	}

	keyword := cString(cKeyword)
	if keyword == "" {
		return 0
	}

	maxLimit := int(limit)
	if maxLimit <= 0 {
		maxLimit = 10
	}

	isExact := (exact != 0)
	results := searchWordParallel(dict, keyword, isExact)

	if len(results) == 0 {
		return 0
	}

	// 結果をテキスト形式で整形（タブ区切り: 漢字 \t 読み \t 意味 \n）
	var sb strings.Builder
	for i, res := range results {
		if i >= maxLimit {
			break
		}
		dispKanji := res.Kanji
		if dispKanji == "" {
			dispKanji = res.Kana
		}
		sb.WriteString(fmt.Sprintf("%s\t%s\t%s\n", dispKanji, res.Kana, res.Glosses))
	}

	return copyToCBuf(sb.String(), outBuf, maxLen)
}

//export jmdict_format
func jmdict_format(cResults *C.char, outBuf *C.char, maxLen C.int) C.int {
	if cResults == nil {
		return 0
	}

	raw := C.GoBytes(unsafe.Pointer(cResults), C.int(C.strlen(cResults)))
	results := toUTF8(raw)
	var sb strings.Builder
	for _, line := range strings.Split(strings.TrimRight(results, "\r\n"), "\n") {
		line = strings.TrimSuffix(line, "\r")
		fields := strings.SplitN(line, "\t", 3)
		if len(fields) != 3 {
			continue
		}
		fmt.Fprintf(&sb, "%s [%s]\r\n%s\r\n\r\n", fields[0], fields[1], fields[2])
	}

	return copyToCBuf(sb.String(), outBuf, maxLen)
}

//export jmdict_free
func jmdict_free() {
	dictMu.Lock()
	globalDict = nil
	dictMu.Unlock()
}

func searchWordParallel(dict *Dictionary, keyword string, exact bool) []Entry {
	var results []Entry
	var mu sync.Mutex
	var wg sync.WaitGroup

	numWorkers := 4
	chunkSize := (len(dict.Entries) + numWorkers - 1) / numWorkers

	for i := 0; i < numWorkers; i++ {
		start := i * chunkSize
		end := start + chunkSize
		if start >= len(dict.Entries) {
			break
		}
		if end > len(dict.Entries) {
			end = len(dict.Entries)
		}

		wg.Add(1)
		go func(subEntries []Entry) {
			defer wg.Done()
			var localResults []Entry

			for _, entry := range subEntries {
				isMatch := false
				kanjis := strings.Split(entry.Kanji, " / ")

				if exact {
					for _, k := range kanjis {
						if strings.TrimSpace(k) == keyword {
							isMatch = true
							break
						}
					}
				} else {
					for _, k := range kanjis {
						if strings.HasPrefix(strings.TrimSpace(k), keyword) {
							isMatch = true
							break
						}
					}
				}

				if isMatch {
					localResults = append(localResults, entry)
				}
			}

			if len(localResults) > 0 {
				mu.Lock()
				results = append(results, localResults...)
				mu.Unlock()
			}
		}(dict.Entries[start:end])
	}

	wg.Wait()

	if !exact {
		sort.Slice(results, func(i, j int) bool {
			lenI := len([]rune(results[i].Kanji))
			if lenI == 0 {
				lenI = len([]rune(results[i].Kana))
			}
			lenJ := len([]rune(results[j].Kanji))
			if lenJ == 0 {
				lenJ = len([]rune(results[j].Kana))
			}
			return lenI < lenJ
		})
	}

	return results
}

func main() {}
