import xml.etree.ElementTree as ET
import csv
# http://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz
def parse_jmdict(xml_path, csv_path):
    print("JMdictを解析中...（数分かかる場合があります）")

    # XMLの読み込み
    tree = ET.parse(xml_path)
    root = tree.getroot()

    with open(csv_path, 'w', encoding='utf-8-sig', newline='') as f:
        writer = csv.writer(f)
        # ヘッダーの書き込み
        writer.writerow(['kanji', 'kana', 'glosses'])

        for entry in root.findall('entry'):
            # 1. 表記（漢字など）の取得
            kanji_list = [k_ele.find('keb').text for k_ele in entry.findall('k_ele')]
            kanji = " / ".join(kanji_list) if kanji_list else ""

            # 2. 読み（かな）の取得
            kana_list = [r_ele.find('reb').text for r_ele in entry.findall('r_ele')]
            kana = " / ".join(kana_list) if kana_list else ""

            # 漢字表記がない場合は、読みをメインの表記とする
            if not kanji:
                kanji = kana

            # 3. 意味（英語）の取得
            gloss_list = []
            for sense in entry.findall('sense'):
                senses = [gloss.text for gloss in sense.findall('gloss') if gloss.text]
                if senses:
                    gloss_list.append(", ".join(senses))
            glosses = " || ".join(gloss_list)

            # CSVに書き込み
            writer.writerow([kanji, kana, glosses])

    print(f"変換が完了しました！ 保存先: {csv_path}")

# 使い方
parse_jmdict("JMdict_e", "jmdict_simple.csv")