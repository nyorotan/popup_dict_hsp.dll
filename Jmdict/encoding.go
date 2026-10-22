package main

import (
	"golang.org/x/text/encoding/japanese"
)

func toShiftJIS(s string) []byte {
	encoder := japanese.ShiftJIS.NewEncoder()
	encoded := make([]byte, 0, len(s))
	for _, r := range s {
		charBytes, err := encoder.Bytes([]byte(string(r)))
		if err != nil {
			encoded = append(encoded, '?')
			continue
		}
		encoded = append(encoded, charBytes...)
	}
	return encoded
}
