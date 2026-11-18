"""
Предметы и рецепты из карты Anime Team Survival 4.9v → data_items.gd.
Здесь записаны исходные числа карты; скрипт делит их на коэффициенты, чтобы
они подходили к масштабу этой игры, и пишет GDScript-таблицу.
Запуск: python gen_items.py <путь к game/scripts/data_items.gd>
"""
import sys, os, json

K_PRICE = 90.0   # цены
K_ATTR = 8.0     # сила / ловкость / интеллект / все атрибуты
K_DMG = 25.0     # урон, поглощение, урон ауры
K_HP = 20.0      # здоровье, лечение
K_ARMOR = 5.0    # броня
K_MP = 25.0      # мана
K_REGEN = 10.0   # регенерация

C = {  # цвета классов для иконок
    "red": (1.0, 0.3, 0.3), "blue": (0.35, 0.55, 1.0), "green": (0.35, 1.0, 0.5), "gold": (1.0, 0.8, 0.3),
    "violet": (0.75, 0.45, 1.0), "white": (0.85, 0.88, 0.95), "dark": (0.45, 0.25, 0.55), "orange": (1.0, 0.55, 0.2),
    "teal": (0.4, 0.95, 0.95), "brown": (0.7, 0.55, 0.35), "pink": (1.0, 0.55, 0.8),
}

# id: (имя, имя в карте, цена в карте, класс, иконка, цвет, статы карты, доп)
BASE = {
    # ---- Храм (Temple)
    "remains": ("Останки виновного", "Remains of the Guilty", 50000, "D", "skull", "red",
                {"damage": 350, "str": 20}, {"active": {"type": "attack_buff", "pct": 0.2, "dur": 6, "cd": 30}}),
    "orb_fire": ("Сфера огня", "Orb of Fire", 150000, "D", "orb", "orange", {"str": 200}, {}),
    "orb_water": ("Сфера воды", "Orb of Water", 150000, "D", "orb", "blue", {"int": 200}, {}),
    "orb_wind": ("Сфера ветра", "Orb of Wind", 150000, "D", "orb", "green", {"agi": 200}, {}),
    "glove_demonic": ("Перчатка демонического огня", "Glove of the Demonic Fire", 125800, "D", "glove", "red",
                      {"damage": 1000, "armor": 20}, {}),
    "light_keyblade": ("Светлый клинок-ключ", "Light KeyBlade", 170000, "D", "key_blade", "white", {"damage": 2000}, {}),
    "dark_keyblade": ("Тёмный клинок-ключ", "Dark KeyBlade", 170000, "D", "key_blade", "dark", {"damage": 2000}, {}),
    "chakra_stick": ("Посох чакры", "Stick of Chakra", 20000, "D", "staff", "blue",
                     {"int": 12, "mp": 200}, {"mp_regen": 1.5}),
    "lumber_sword": ("Деревянный меч", "Lumber Sword", 2000, "D", "sword", "brown", {"damage": 50}, {}),
    "spirit_claw": ("Коготь духа", "Spirit Claw", 105386, "D", "claw", "teal", {"damage": 600}, {}),
    "black_sword": ("Чёрный меч демонов", "Black Sword of Deamons", 150000, "D", "sword", "dark", {"damage": 1500}, {}),
    "short_sword": ("Короткий меч", "Short Sword", 40000, "D", "sword", "white", {"damage": 300}, {}),
    # ---- Затерянные руины (Lost Ruin)
    "feather_flame": ("Перо пламени", "Feather Of Flame", 35000, "D", "feather", "orange",
                      {"armor": 10}, {"active": {"type": "mirror", "mult": 0.3, "dur": 8, "cd": 40}}),
    "claws_chaos": ("Когти хаоса", "Claws of the Chaos", 80000, "D", "claw", "violet",
                    {"damage": 200, "int": 100, "mp": 2000}, {}),
    "true_seeing": ("Камень истинного зрения", "True Seeing", 50000, "D", "eye", "gold", {}, {"vision": 6.0}),
    "gold_amulet": ("Золотой амулет", "Gold Amulet", 13200, "D", "amulet", "gold", {}, {"evasion": 0.10}),
    "moon_ring": ("Лунное кольцо", "Moonstone-inset Ring", 6722, "D", "ring", "white", {"all": 12}, {}),
    "rainbow_ring": ("Радужное кольцо", "RainBow Ring", 42500, "D", "ring", "pink", {"all": 100}, {}),
    "ring_regen": ("Кольцо регенерации", "Ring Regeneration", 16000, "D", "ring", "green", {"hp_regen": 10}, {}),
    "glove_speed": ("Перчатки скорости", "Glove Of Speed", 20000, "D", "glove", "gold", {}, {"attack_speed": 0.15}),
    "ruby_ring": ("Рубиновое кольцо", "Ruby-inset Ring", 3000, "D", "ring", "red", {"str": 20}, {}),
    "sapphire_ring": ("Сапфировое кольцо", "Sapphire-inset Ring", 3000, "D", "ring", "blue", {"int": 20}, {}),
    "emerald_ring": ("Изумрудное кольцо", "Emerald-inset Ring", 3000, "D", "ring", "green", {"agi": 20}, {}),
    # ---- Оружейник (Armor Merchant)
    "unknown_item": ("Неизвестный предмет", "Unknown Item", 3000, "D", "gem", "white", {}, {"stun_chance": 0.03}),
    "key_set": ("[Ключ] Ключ сета", "[Unlock] Key Set Item", 210000, "S", "key", "gold",
                {"str": 200, "agi": 200, "int": 200, "hp": 10000}, {}),
    "wind_break": ("Ветролом", "WindBreak", 40000, "D", "armor", "green", {"agi": 20, "armor": 20, "damage": 100}, {}),
    "recipe_element": ("Рецепт стихии", "Recipe Element", 40000, "D", "scroll", "gold", {}, {}),
    "dragon_shield": ("Щит из драконьей чешуи", "Dragon-scale Shield", 30000, "D", "shield", "green",
                      {"armor": 5, "absorb": 300}, {}),
    "lumber_shield": ("Деревянный щит", "Lumber Shield", 3000, "D", "shield", "brown", {"armor": 5}, {}),
    "studded_armor": ("Клёпаный доспех", "Studded Leather Armor", 80000, "D", "armor", "brown", {"armor": 60}, {}),
    "blood_diamond": ("Кровавый алмаз", "Blood Diamond", 25000, "D", "gem", "red", {"hp": 20000}, {}),
    "health_stone": ("Камень здоровья", "Health Stone", 20000, "D", "gem", "pink", {"hp": 6000}, {}),
    "elven_mail": ("Эльфийский доспех", "Elven Plate Mail", 45000, "D", "armor", "white", {"armor": 30}, {}),
    "elixir_health": ("Эликсир здоровья", "Elixir of Health", 14000, "D", "potion", "red",
                      {"hp": 1000}, {"active": {"type": "heal", "amount": 2000, "cd": 30}}),
    # ---- Ботаника Мауриги
    "shinobi_cloak": ("Покров шиноби", "Layer Shinobi", 30000, "D", "cloak", "dark", {}, {"stealth": 1.0}),
    "magic_letter": ("Письмо магии", "Letter of Magic", 105000, "D", "scroll", "violet", {"mp": 50000}, {}),
    # ---- Банк (First Provincial Bank)
    "dragon_skin": ("Драконья кожа", "Dragon Skin", 80000, "D", "armor", "green", {"armor": 100, "hp_regen": 100}, {}),
    "unknown_bone": ("Неизвестная кость", "Unknown Bone", 10000, "D", "bone", "white", {"armor": 50}, {}),
    "orb_nature": ("Сфера природы", "Orb of Nature", 150000, "D", "orb", "teal", {"all": 70}, {}),
    "orb_darkness": ("Сфера тьмы", "Orb of Darkness", 150000, "D", "orb", "dark", {"all": 50, "armor": 50}, {}),
}

# Расходники и книги — цены и числа подобраны под игру (в карте у зелий по 5–15 зарядов)
CONSUMABLES = {
    "potion": {"name": "Зелье лечения", "map": "Potion of Healing", "price": 120, "cls": "D", "icon": "potion",
               "color": "red", "consumable": True, "charges": 5, "heal": 300.0},
    "potion_big": {"name": "Большое зелье лечения", "map": "Potion of Greater Healing", "price": 400, "cls": "D",
                   "icon": "potion", "color": "orange", "consumable": True, "charges": 5, "heal": 1000.0},
    "potion_ultra": {"name": "Ультразелье лечения", "map": "Potion of Ultra Healing", "price": 1200, "cls": "D",
                     "icon": "potion", "color": "pink", "consumable": True, "charges": 5, "heal": 3000.0},
    "mana_potion": {"name": "Малое зелье маны", "map": "Small Mana Potion", "price": 80, "cls": "D", "icon": "potion",
                    "color": "blue", "consumable": True, "charges": 5, "mana": 150.0},
    "mana_potion_big": {"name": "Большое зелье маны", "map": "Large Mana Potion", "price": 300, "cls": "D",
                        "icon": "potion", "color": "violet", "consumable": True, "charges": 5, "mana": 600.0},
    "elixir_invuln": {"name": "Эликсир неуязвимости", "map": "Elixir of Invulnerability", "price": 660, "cls": "D",
                      "icon": "potion", "color": "gold", "consumable": True, "charges": 1, "invuln": 6.0},
    "vamp_potion": {"name": "Вампирское зелье", "map": "Vampiric Potion", "price": 120, "cls": "D", "icon": "potion",
                    "color": "dark", "consumable": True, "charges": 1, "vamp": 15.0},
    "tome_str": {"name": "Книга силы +2", "map": "Tome of Strength", "price": 250, "cls": "D", "icon": "book",
                 "color": "red", "tome": {"str": 2}},
    "tome_agi": {"name": "Книга ловкости +2", "map": "Tome of Agility", "price": 250, "cls": "D", "icon": "book",
                 "color": "green", "tome": {"agi": 2}},
    "tome_int": {"name": "Книга разума +2", "map": "Tome of Intelligence", "price": 250, "cls": "D", "icon": "book",
                 "color": "blue", "tome": {"int": 2}},
    "tome_all": {"name": "Книга знаний +1 ко всем", "map": "Tome of Knowledge", "price": 240, "cls": "D", "icon": "book",
                 "color": "gold", "tome": {"str": 1, "agi": 1, "int": 1}},
    "tome_combat": {"name": "Боевое руководство +5 урона", "map": "Manual of Combat", "price": 200, "cls": "D",
                    "icon": "book", "color": "orange", "tome": {"damage": 5}},
    "tome_exp": {"name": "Книга опыта", "map": "Tome of Experience", "price": 80, "cls": "D", "icon": "book",
                 "color": "violet", "tome": {"xp": 150}},
}

# id: (имя, имя в карте, класс, иконка, цвет, компоненты, статы карты, доп)
RECIPES = {
    # ---- Галактика Шаринга (C/B)
    "resist_skin": ("Прочная кожа", "Resistan Skin", "C+", "armor", "brown",
                    ["health_stone", "lumber_shield"], {"armor": 50}, {}),
    "water_shield": ("Водный щит", "Water Shield", "C", "shield", "blue",
                     ["chakra_stick", "sapphire_ring"], {"int": 60}, {"magic_resist": 0.05}),
    "ancestral_spear": ("Копьё предков", "Ancestral Spear", "C", "spear", "gold",
                        ["lightning_sword", "black_sword", "dark_keyblade"], {"damage": 6000}, {}),
    "health_staff": ("Посох здоровья", "Stick of Health", "C+", "staff", "green",
                     ["elven_mail", "ring_regen"], {}, {"lifesteal": 0.15}),
    "blade_sin": ("Клинок греха", "Blade of Sin", "C", "sword", "violet",
                  ["chakra_stick", "black_sword", "moon_ring"], {"damage": 1500, "all": 12}, {"mana_burn": 10.0}),
    "soul_nature": ("Душа природы", "Soul of Nature", "B", "heart", "green",
                    ["blood_diamond", "elixir_health", "rainbow_ring"], {"hp": 20000},
                    {"active": {"type": "heal", "amount": 20000, "cd": 60}}),
    "antimagic": ("Антимагический костюм", "Anti Magic Costume", "D+", "armor", "violet",
                  ["lumber_shield", "lumber_sword", "unknown_item"], {"damage": 100, "armor": 5},
                  {"active": {"type": "spell_shield", "dur": 5, "cd": 50}}),
    "dark_glove": ("Тёмная перчатка", "Dark Glove", "C", "glove", "dark",
                   ["glove_speed", "emerald_ring"], {}, {"attack_speed": 0.30}),
    "x_keyblade": ("Двойной Х-клинок", "X Dual Keyblade", "B+", "key_blade", "teal",
                   ["dark_keyblade", "light_keyblade", "dark_glove"], {"damage": 4000},
                   {"cold": 1.0, "active": {"type": "freeze_nova", "dmg": 3000, "radius": 9.0, "freeze": 2.0, "cd": 40}}),
    "lightning_sword": ("Молниевый меч", "Lightning Sword", "B", "sword", "teal",
                        ["short_sword", "spirit_claw"], {"damage": 900}, {}),
    "leaf_ygg": ("Лист Иггдрасиля", "Leaf of Yggdrasil", "B", "leaf", "green",
                 ["antimagic", "magic_letter", "emerald_ring"], {"damage": 50, "armor": 20, "mp": 10000},
                 {"active": {"type": "root", "dur": 3.0, "range": 14.0, "cd": 50}}),
    # ---- Чёрный торговец (A)
    "dark_seal": ("Тёмная печать", "Dark Seal", "B+", "seal", "dark",
                  ["elem_wind", "orb_wind", "emerald_ring", "rainbow_ring", "shinobi_cloak"], {"agi": 1500},
                  {"active": {"type": "invis", "dur": 10, "cd": 60}}),
    "skin_ygg": ("Кожа Иггдрасиля", "Skin of Yggdrasil", "A", "armor", "green",
                 ["dragon_skin", "resist_skin", "chakra_stick", "lumber_shield"], {"armor": 200, "hp": 10000},
                 {"reflect": 0.05}),
    "lock_on": ("Захват цели!", "Lock ON!", "A", "scope", "red",
                ["remains", "dark_glove", "sinon_crit", "glove_demonic", "key_set"], {"damage": 2400, "all": 250},
                {"crit_chance": 0.30, "crit_mult": 3.0,
                 "active": {"type": "snipe", "dmg": 10000, "stun": 4.0, "cd": 30}}),
    "rejuvenation": ("Омоложение", "Rejuvenation", "A+", "heart", "pink",
                     ["soul_nature", "magic_letter", "blood_diamond", "health_staff", "ring_regen"],
                     {"hp": 120000, "hp_regen": 100}, {"active": {"type": "heal", "amount": 50000, "cd": 60}}),
    "immortality": ("Благословение бессмертия", "Blessing of Immortality", "A+", "halo", "gold",
                    ["unknown_item", "dragon_shield", "gold_amulet", "soul_nature", "elixir_invuln"],
                    {"hp": 60000, "armor": 50}, {"evasion": 0.20, "active": {"type": "immortal", "dur": 5, "cd": 30}}),
    "gem_wishes": ("Камень желаний", "Gem of Wishes", "A+", "gem", "blue",
                   ["elven_mail", "elem_water", "claws_chaos", "chakra_stick"], {"armor": 80, "int": 600, "mp": 10000},
                   {"active": {"type": "hex", "dur": 3.0, "range": 14.0, "cd": 60}}),
    "twins": ("Двойники", "Twins (иллюзии)", "A", "mirror", "pink",
              ["feather_flame", "elem_fire", "elixir_health"], {"hp": 10000, "armor": 20, "damage": 200},
              {"active": {"type": "mirror", "mult": 1.0, "dur": 10, "cd": 120}}),
    "seven_senses": ("Танец семи чувств", "Dance of the Seven Senses", "A", "sword", "pink",
                     ["remains", "spirit_claw", "x_keyblade"], {"damage": 6000}, {"seven": 0.25}),
    "seven_sin": ("Семь грехов", "The Seven Sin", "A", "sword", "red",
                  ["blade_sin", "health_stone", "dragon_shield", "orb_wind"], {"damage": 4000, "all": 100, "absorb": 300},
                  {"mana_burn": 20.0}),
    "sinon_crit": ("[Синон] Критический удар", "[Sinon] Critical Strike", "B+", "scope", "teal",
                   ["rainbow_ring", "lightning_sword", "glove_speed", "health_stone"], {"damage": 240, "all": 36},
                   {"crit_chance": 0.30, "crit_mult": 3.0}),
    "shinobu_lifesteal": ("[Шинобу] Вампиризм", "[Shinobu] LifeSteal", "B+", "fang", "red",
                          ["health_stone", "health_staff", "ruby_ring", "gold_amulet", "black_sword"],
                          {"all": 20, "damage": 2000}, {"lifesteal": 0.23}),
    # ---- Дом выживания (S)
    "pandora": ("Ящик Пандоры", "Pandora Box", "S+", "box", "violet",
                ["x_keyblade", "lost_relic", "unknown_item", "lightning_sword", "dark_keyblade"], {"damage": 30000},
                {"crit_chance": 0.30, "crit_mult": 5.0, "seven": 1.0, "active": {"type": "spell_shield", "dur": 12, "cd": 60}}),
    "blessing": ("Благословение духа", "Blessing (призыв духа)", "S", "halo", "pink",
                 ["rainbow_ring", "rainbow_ring", "black_sword", "glove_demonic", "dragon_skin", "soul_nature"],
                 {"all": 200, "hp": 60000}, {"active": {"type": "spirit", "dur": 30, "cd": 100}}),
    "legion_sky": ("Легион небес", "Legion of the Sky", "S", "shield", "gold",
                   ["dragon_shield", "studded_armor", "elven_mail", "unknown_item", "resist_skin", "key_set"],
                   {"all": 100, "armor": 100}, {"aura_armor": 20.0}),
    "lost_flame": ("Утраченное пламя дракона", "Lost Flame of Dragon", "S", "flame", "orange",
                   ["magic_letter", "recipe_element", "orb_fire", "orb_wind", "orb_water"], {"all": 400},
                   {"burn": 5000}),
    "subzero": ("Ледяной щит", "Sub-Zero Shield", "A+", "shield", "teal",
                ["orb_water", "water_shield", "elven_mail", "rainbow_ring", "antimagic"],
                {"int": 300, "str": 100, "agi": 100, "mp": 100000}, {"magic_resist": 0.20, "reduction": 0.20}),
    "lost_relic": ("Утраченная реликвия", "Lost Relic", "S", "star", "gold",
                   ["seven_senses", "ancestral_spear", "black_sword", "glove_demonic", "short_sword"], {"damage": 16000},
                   {"crit_chance": 0.30, "crit_mult": 3.0, "seven": 0.40}),
    "niflheim": ("[Миюки] Нифльхейм", "[Miyuki] Niflheim", "S", "snowflake", "blue",
                 ["sinon_crit", "shinobu_lifesteal", "orb_fire", "orb_water", "orb_wind", "glove_demonic"],
                 {"all": 300, "damage": 6000}, {"lifesteal": 0.23, "crit_chance": 0.35, "crit_mult": 5.0}),
    "elem_wind": ("Стихия ветра", "Element Wind", "B+", "orb", "green",
                  ["wind_break", "emerald_ring", "recipe_element", "orb_wind"], {"damage": 300, "agi": 350, "armor": 10}, {}),
    "elem_fire": ("Стихия огня", "Element Fire", "B+", "orb", "orange",
                  ["orb_fire", "ruby_ring", "recipe_element", "remains"], {"str": 350, "damage": 300, "hp_regen": 20}, {}),
    "elem_water": ("Стихия воды", "Element Water", "B+", "orb", "blue",
                   ["orb_water", "sapphire_ring", "claws_chaos", "recipe_element"], {"int": 340, "damage": 300, "mp": 2000}, {}),
    # ---- Тайная лавка (Shiro)
    "thirst_blood": ("Жажда крови", "Thirst Blood", "A", "fang", "red",
                     ["true_seeing", "elem_fire", "black_sword", "water_shield", "unknown_bone"], {"damage": 4000, "all": 300},
                     {"active": {"type": "confuse", "radius": 9.0, "slow": 0.6, "dur": 5.0, "cd": 80}}),
    "true_heart": ("Истинное сердце", "True Heart", "S", "heart", "gold",
                   ["elem_fire", "elem_wind", "elem_water"], {"all": 700}, {}),
    "crystal_sephira": ("Кристалл Сефиры", "Crystal Sephira", "A+", "gem", "teal",
                        ["orb_fire", "orb_water", "orb_wind", "orb_nature", "orb_darkness"], {"all": 400, "armor": 80}, {}),
    "yin_yang": ("Инь-Ян", "Yin Yang", "S", "yinyang", "white",
                 ["soul_nature", "crystal_sephira", "unknown_item", "orb_darkness", "orb_wind"],
                 {"hp": 200000, "armor": 200, "hp_regen": 1500}, {}),
    "mark_divine": ("Божественная метка", "Mark Divine", "S", "halo", "white",
                    ["rejuvenation", "leaf_ygg", "orb_nature", "orb_wind"], {"hp": 220000},
                    {"active": {"type": "heal_pct", "pct": 1.0, "cd": 80}}),
}

# Ультимативный сет: [стихия, сфера] по основному атрибуту героя + Душа природы + Антимагия + Ключ + Ex
# Статы — из «[Set] <герой> Ultimate Item» карты (урон, здоровье, броня, атрибуты).
SETS = {
    "akame": ("[Сет] Ультимативный: Акаме", "Akame Ultimate Item", "fire",
        {"damage": 10000, "str": 300, "agi": 300, "hp": 20000}, "Мурасамэ: Козырь"),
    "esdeath": ("[Сет] Ультимативный: Эсдес", "Esdeath Ultimate Item", "water",
        {"damage": 6000, "hp": 30000, "agi": 400, "int": 600}, "Махин Кэнгэн: Махападма"),
    "ichigo": ("[Сет] Ультимативный: Ичиго", "Ichigo Ultimate Item", "fire",
        {"damage": 6000, "str": 600, "agi": 200, "int": 100, "hp": 30000}, "Сайго-но Гэцуга Тэнсё: Мугэцу"),
    "miyuki": ("[Сет] Ультимативный: Миюки", "Miyuki Ultimate Item", "water",
        {"damage": 6000, "hp": 30000, "agi": 400, "int": 600}, "Систематическая магия: Инферно"),
    "shiro": ("[Сет] Ультимативный: Сиро", "Shiro Ultimate Item", "wind",
        {"damage": 4000, "hp": 30000, "str": 500, "agi": 500, "int": 200}, "Шахматная доска: Детский мат"),
    "origami": ("[Сет] Ультимативный: Оригами", "Origami Ultimate Item", "water",
        {"damage": 6000, "hp": 20000, "agi": 300, "int": 600}, "Инверсия: Сатана"),
    "archer": ("[Сет] Ультимативный: Арчер", "Archer Ultimate Item", "fire",
        {"damage": 5000, "str": 600, "agi": 160, "int": 100, "hp": 25000}, "Unlimited Blade Works"),
    "asuna": ("[Сет] Ультимативный: Асуна", "Asuna Ultimate Item", "wind",
        {"damage": 8000, "hp": 15000, "str": 300, "agi": 600, "int": 100}, "Окончательный эсток"),
    "brs": ("[Сет] Ультимативный: Блэк Рок Шутер", "Black Rock Shooter Ultimate Item", "wind",
        {"damage": 6000, "str": 200, "agi": 600, "int": 100, "hp": 20000}, "Абсолютная пушка"),
    "est": ("[Сет] Ультимативный: Эст", "Est Ultimate Item", "water",
        {"armor": 100, "hp": 20000, "str": 200, "agi": 200, "int": 700}, "Гладиус Мандо: Абсолютум Тираннидис"),
    "erza": ("[Сет] Ультимативный: Эльза", "Erza Ultimate Item", "fire",
        {"armor": 200, "str": 600, "agi": 600, "int": 100, "hp": 20000}, "Ультимативное комбо"),
    "inori": ("[Сет] Ультимативный: Инори", "Inori Ultimate Item", "water",
        {"damage": 6000, "hp": 15000, "agi": 600, "int": 600}, "Кристаллизация: Апокалипсис пустоты"),
    "kirito": ("[Сет] Ультимативный: Кирито", "Kirito Ultimate Item", "wind",
        {"damage": 6000, "hp": 25000, "str": 300, "agi": 600}, "Звёздный поток"),
    "kotori": ("[Сет] Ультимативный: Котори", "Kotori Ultimate Item", "fire",
        {"damage": 6000, "str": 600, "agi": 200, "int": 100, "hp": 30000}, "Камаэль: Пушка Мегиддо"),
    "kurumi": ("[Сет] Ультимативный: Куруми", "Kurumi Ultimate Item", "wind",
        {"damage": 4000, "hp": 20000, "str": 400, "agi": 600, "int": 100}, "Безумное комбо"),
    "natsu": ("[Сет] Ультимативный: Нацу", "Natsu Ultimate Item", "fire",
        {"damage": 4000, "str": 600, "agi": 200, "int": 100, "hp": 36000}, "Гурэн Хоо Кэн"),
    "misaka": ("[Сет] Ультимативный: Мисака", "Misaka Ultimate Item", "water",
        {"damage": 6000, "hp": 20000, "agi": 400, "int": 600}, "Рейлган"),
    "miku": ("[Сет] Ультимативный: Мику", "Miku Ultimate Item", "water",
        {"armor": 100, "hp": 20000, "str": 200, "agi": 200, "int": 700}, "Музыкальный тур"),
    "sinon": ("[Сет] Ультимативный: Синон", "Sinon Ultimate Item", "wind",
        {"damage": 8000, "hp": 16000, "str": 200, "agi": 800, "int": 200}, "Хаотичное пространство"),
    "shana": ("[Сет] Ультимативный: Шана", "Shana Ultimate Item", "fire",
        {"damage": 6000, "hp": 28000, "str": 600, "agi": 300}, "Божественный призыв: Тэмпа Дзёсай"),
    "shinobu": ("[Сет] Ультимативный: Синобу", "Shinobu Ultimate Item", "fire",
        {"damage": 8000, "str": 600, "hp": 40000}, "Кисс-шот Ацеролаорион Хартандерблейд"),
    "sephiroth": ("[Сет] Ультимативный: Сефирот", "Sephiroth Ultimate Item", "wind",
        {"damage": 6000, "hp": 20000, "str": 300, "agi": 400, "int": 100}, "Метеоритный дождь"),
    "saber": ("[Сет] Ультимативный: Сейбер Лили", "Saber Ultimate Item", "fire",
        {"damage": 6000, "str": 450, "agi": 450, "hp": 20000}, "Экскалибур"),
    "shiki": ("[Сет] Ультимативный: Сики", "Shiki Ultimate Item", "wind",
        {"damage": 10000, "hp": 30000, "agi": 600}, "Искусство убийцы"),
    "tamamo": ("[Сет] Ультимативный: Тамамо", "Tama Ultimate Item", "water",
        {"armor": 100, "hp": 20000, "str": 100, "agi": 100, "int": 600}, "Восьмикратное благословение Аматэрасу"),
    "tina": ("[Сет] Ультимативный: Тина", "Tina Ultimate Item", "wind",
        {"damage": 8000, "hp": 16000, "str": 200, "agi": 800, "int": 200}, "Приказ роботам: Занять пространство"),
    "tohka": ("[Сет] Ультимативный: Тока", "Tohka Ultimate Item", "fire",
        {"damage": 6000, "str": 450, "agi": 450, "hp": 20000}, "Король демонов: Нахема"),
    "tsurara": ("[Сет] Ультимативный: Цурара", "Tsurara Ultimate Item", "wind",
        {"armor": 100, "hp": 15000, "str": 500, "agi": 500, "int": 200}, "Айсберг"),
    "wrs": ("[Сет] Ультимативный: Уайт Рок Шутер", "White Rock Shooter Ultimate Item", "wind",
        {"damage": 8000, "hp": 15000, "str": 300, "agi": 600, "int": 100}, "Луч благодарного солнца"),
    "yaya": ("[Сет] Ультимативный: Яя", "Yaya Ultimate Item", "fire",
        {"damage": 8000, "str": 400, "agi": 200, "int": 100, "hp": 20000}, "Последний оплот"),
    "yuu": ("[Сет] Ультимативный: Ю", "Yuu Ultimate Item", "water",
        {"armor": 100, "hp": 20000, "str": 100, "agi": 100, "int": 600}, "Последний демон — Хеллсайз"),
    "yoshino": ("[Сет] Ультимативный: Ёсино", "Yoshino Ultimate Item", "water",
        {"armor": 200, "hp": 10000, "str": 200, "int": 800}, "Задкиэль: Ледниковый период"),
}

# Личные предметы Ex: имя героя в названии и цвет
EX = {
    "akame": ("Акаме", "Akame", (0.85, 0.12, 0.18)),
    "esdeath": ("Эсдес", "Esdeath", (0.45, 0.75, 1.00)),
    "ichigo": ("Ичиго", "Kurosaki Ichigo", (1.00, 0.55, 0.15)),
    "miyuki": ("Миюки", "Shiba Miyuki", (0.55, 0.80, 1.00)),
    "shiro": ("Сиро", "[ ] Shiro", (0.85, 0.85, 0.95)),
    "origami": ("Оригами", "Tobiichi Origami", (0.92, 0.92, 1.00)),
    "archer": ("Арчер", "Archer", (0.85, 0.15, 0.15)),
    "asuna": ("Асуна", "Yuuki Asuna", (0.55, 1.00, 0.55)),
    "brs": ("Блэк Рок Шутер", "\u0411\u043b\u044d\u043a \u0420\u043e\u043a \u0428\u0443\u0442\u0435\u0440", (0.25, 0.45, 1.00)),
    "est": ("Эст", "Est", (0.55, 0.55, 1.00)),
    "erza": ("Эльза", "Erza Scarlet", (0.90, 0.25, 0.20)),
    "inori": ("Инори", "Yuzuriha Inori", (0.85, 0.35, 0.65)),
    "kirito": ("Кирито", "Kirigaya Kazuto", (0.40, 0.40, 0.50)),
    "kotori": ("Котори", "Kotori Itsuka", (0.95, 0.30, 0.25)),
    "kurumi": ("Куруми", "Tokisaki Kurumi", (0.75, 0.10, 0.15)),
    "natsu": ("Нацу", "Natsu Dragneel", (1.00, 0.45, 0.10)),
    "misaka": ("Мисака", "Misaka Mikoto [Railgun]", (0.35, 0.70, 1.00)),
    "miku": ("Мику", "Hatsune Miku", (0.30, 0.85, 0.80)),
    "sinon": ("Синон", "Asada Shino", (0.45, 0.85, 0.75)),
    "shana": ("Шана", "Shana", (1.00, 0.35, 0.15)),
    "shinobu": ("Синобу", "Shinobu", (1.00, 0.85, 0.35)),
    "sephiroth": ("Сефирот", "Sephiroth", (0.75, 0.75, 0.85)),
    "saber": ("Сейбер Лили", "Saber Lily", (0.95, 0.85, 0.40)),
    "shiki": ("Сики", "Ryougi Shiki", (0.55, 0.45, 0.85)),
    "tamamo": ("Тамамо", "Tamamo", (1.00, 0.50, 0.75)),
    "tina": ("Тина", "Tina Sprout", (0.50, 0.95, 0.50)),
    "tohka": ("Тока", "Tohka Yatogami", (0.70, 0.35, 0.95)),
    "tsurara": ("Цурара", "Oikawa Tsurara", (0.60, 0.85, 1.00)),
    "wrs": ("Уайт Рок Шутер", "\u0423\u0430\u0439\u0442 \u0420\u043e\u043a \u0428\u0443\u0442\u0435\u0440", (0.90, 0.90, 0.95)),
    "yaya": ("Яя", "Yaya [Machine Doll]", (0.80, 0.45, 0.35)),
    "yuu": ("Ю", "Yuu", (0.60, 0.35, 0.75)),
    "yoshino": ("Ёсино", "Yoshino", (0.55, 0.80, 1.00)),
}

SHOPS = [
    ("Храм", "Temple", ["remains", "orb_fire", "orb_water", "orb_wind", "glove_demonic", "light_keyblade",
                        "dark_keyblade", "chakra_stick", "lumber_sword", "spirit_claw", "black_sword", "short_sword"]),
    ("Руины", "Lost Ruin", ["feather_flame", "claws_chaos", "true_seeing", "gold_amulet", "moon_ring", "rainbow_ring",
                           "ring_regen", "glove_speed", "ruby_ring", "sapphire_ring", "emerald_ring"]),
    ("Оружейник", "Armor Merchant", ["unknown_item", "key_set", "wind_break", "recipe_element", "dragon_shield",
                                    "lumber_shield", "studded_armor", "blood_diamond", "health_stone", "elven_mail",
                                    "elixir_health"]),
    ("Ботаника", "Mauriga's Botanicals", ["shinobi_cloak", "magic_letter", "elixir_invuln", "mana_potion",
                                         "mana_potion_big", "potion", "potion_big", "potion_ultra", "vamp_potion",
                                         "short_sword"]),
    ("Банк", "First Provincial Bank", ["dragon_skin", "unknown_bone", "orb_nature", "orb_darkness"]),
    ("Камень силы", "Power Stone", ["tome_str", "tome_agi", "tome_int", "tome_all", "tome_combat", "tome_exp"]),
    ("Галактика", "Galaxy Sharinga", ["resist_skin", "water_shield", "ancestral_spear", "health_staff", "blade_sin",
                                     "soul_nature", "antimagic", "dark_glove", "x_keyblade", "lightning_sword", "leaf_ygg"]),
    ("Чёрный торговец", "Black Percher Merchant", ["dark_seal", "skin_ygg", "lock_on", "rejuvenation", "immortality",
                                                  "gem_wishes", "twins", "seven_senses", "seven_sin", "sinon_crit",
                                                  "shinobu_lifesteal"]),
    ("Дом выживания", "Survival Home", ["set_" + h for h in SETS] + ["pandora", "blessing", "legion_sky",
                                       "lost_flame", "subzero", "lost_relic", "niflheim", "elem_wind", "elem_fire",
                                       "elem_water"]),
    ("Тайная", "Shiro [Ruler of Game]", ["thirst_blood", "true_heart", "crystal_sephira", "yin_yang", "mark_divine"]),
]

SCALE = {"str": K_ATTR, "agi": K_ATTR, "int": K_ATTR, "all": K_ATTR, "damage": K_DMG, "absorb": K_DMG, "burn": K_DMG,
         "hp": K_HP, "armor": K_ARMOR, "mp": K_MP, "hp_regen": K_REGEN}


def rnd5(v):
    return int(max(5, round(v / 5.0) * 5))


def scale_stats(raw):
    out = {}
    for k, v in raw.items():
        s = v / SCALE.get(k, 1.0)
        if k in ("hp", "mp", "damage", "armor", "str", "agi", "int", "all"):
            s = round(s) if s >= 2 else round(s, 1)
        else:
            s = round(s, 2)
        out[k] = s
    return out


def scale_active(a):
    a = dict(a)
    if a["type"] == "heal":
        a["amount"] = round(a["amount"] / K_HP)
    if a["type"] in ("freeze_nova", "snipe"):
        a["dmg"] = round(a["dmg"] / K_DMG)
    return a


items = {}
for k, (name, mname, price, cls, icon, col, raw, extra) in BASE.items():
    d = {"name": name, "map": mname, "price": rnd5(price / K_PRICE), "cls": cls, "icon": icon, "color": C[col]}
    d.update(scale_stats(raw))
    for ek, ev in extra.items():
        d[ek] = scale_active(ev) if ek == "active" else ev
    items[k] = d
for k, d in CONSUMABLES.items():
    d = dict(d)
    d["color"] = C[d["color"]]
    items[k] = d


def total(i):
    d = items[i]
    return d["price"] + sum(total(c) for c in d.get("recipe", []))


pending = dict(RECIPES)
for hero, (name, mname, elem, raw, dname) in SETS.items():
    orb = {"fire": "orb_fire", "water": "orb_water", "wind": "orb_wind"}[elem]
    pending["set_" + hero] = (name, mname, "S+", "set", "gold",
                              ["elem_" + elem, orb, "soul_nature", "antimagic", "key_set", "ex_" + hero], raw,
                              {"hero": hero, "no_sell": True, "note": "Открывает способность [D]: %s." % dname})
    exn, exmap, excol = EX[hero]
    items["ex_" + hero] = {"name": "Ex [%s]" % exn, "map": "Ex [%s]" % exmap, "price": 0, "cls": "Ex", "icon": "ex",
                           "color": excol, "hero": hero, "no_sell": True,
                           "note": "Личный предмет героя. Нужен для Ультимативного сета."}
while pending:
    progressed = False
    for k in list(pending):
        name, mname, cls, icon, col, comp, raw, extra = pending[k]
        if all(c in items for c in comp):
            ctot = sum(total(c) for c in comp)
            d = {"name": name, "map": mname, "price": rnd5(ctot * 0.15), "cls": cls, "icon": icon, "color": C[col],
                 "recipe": comp}
            d.update(scale_stats(raw))
            for ek, ev in extra.items():
                d[ek] = scale_active(ev) if ek == "active" else ev
            items[k] = d
            del pending[k]
            progressed = True
    if not progressed:
        raise SystemExit("цикл в рецептах: %s" % list(pending))


def gd(v, ind=1):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(float(v)) if isinstance(v, float) else str(v)
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, tuple):
        return "Color(%.2f, %.2f, %.2f)" % v
    if isinstance(v, list):
        return "[" + ", ".join(gd(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{" + ", ".join("%s: %s" % (json.dumps(k), gd(x)) for k, x in v.items()) + "}"
    raise TypeError(v)


lines = ["class_name ItemData", "## Сгенерировано tools/gen_items.py из данных карты Anime Team Survival 4.9v.",
         "## Не редактируйте вручную — правьте генератор.", "",
         "const ITEMS := {"]
for k, d in items.items():
    lines.append("\t%s: %s," % (json.dumps(k), gd(d)))
lines.append("}")
lines.append("")
# ---------------------------------------------------------------- вкладки лавки по типу предмета
# В какой лавке карты продаётся предмет — для подсказки
shop_of = {}
for title, mname, ids in SHOPS:
    for i in ids:
        assert i in items, i
        shop_of.setdefault(i, title)


def score(d):
    g = lambda k: float(d.get(k, 0))
    act = d.get("active", {}).get("type", "")
    atk = g("damage") + g("attack_speed") * 150 + g("crit_chance") * g("crit_mult") * 120 + g("lifesteal") * 200 \
        + g("seven") * 200 + g("stun_chance") * 400 + g("mana_burn") * 2 + g("cold") * 20
    dfn = g("hp") * 0.04 + g("armor") * 3 + g("hp_regen") * 3 + g("evasion") * 200 + g("absorb") * 2 \
        + g("reflect") * 300 + g("reduction") * 200 + g("aura_armor") * 2
    att = g("str") + g("agi") + g("int") + g("all") * 3
    mag = g("mp") * 0.05 + g("mp_regen") * 10 + g("vision") * 5 + g("stealth") * 40 + g("magic_resist") * 200 \
        + g("burn") * 0.02 + (30 if act in ("spell_shield", "invis", "hex", "root", "confuse", "mirror") else 0)
    return {"attrs": att, "attack": atk, "defense": dfn, "magic": mag}


SET_PARTS = {"key_set", "soul_nature", "antimagic", "recipe_element", "elem_fire", "elem_water", "elem_wind",
             "orb_fire", "orb_water", "orb_wind"}
CATS = [("potions", "Зелья и книги"), ("attrs", "Атрибуты"), ("attack", "Атака"), ("defense", "Защита"),
        ("magic", "Магия и особое"), ("set", "Ультимативный сет")]
tabs = {k: [] for k, _ in CATS}
for k, d in items.items():
    if d["cls"] == "Ex":
        continue
    if k.startswith("set_"):
        tabs["set"].append(k)
        continue
    if d.get("consumable") or "tome" in d:
        tabs["potions"].append(k)
        continue
    if k in SET_PARTS:
        tabs["set"].append(k)
    if k.startswith("orb_"):
        cat = "attrs"
    else:
        sc = score(d)
        cat = max(sc, key=sc.get) if max(sc.values()) > 0 else "magic"
    tabs[cat].append(k)
    d["shop"] = shop_of.get(k, "")
for k in tabs["potions"] + tabs["set"]:
    items[k]["shop"] = shop_of.get(k, "")

lines.append("const SHOP_TABS := [")
for key, title in CATS:
    ids = tabs[key]
    simple = sorted([i for i in ids if "recipe" not in items[i]], key=lambda i: (items[i]["price"], i))
    built = sorted([i for i in ids if "recipe" in items[i] and not i.startswith("set_")], key=lambda i: (total(i), i))
    sets = [i for i in ids if i.startswith("set_")]
    sections = []
    if key == "potions":
        sections.append({"title": "Зелья", "items": [i for i in simple if "tome" not in items[i]]})
        sections.append({"title": "Книги (действуют сразу)", "items": [i for i in simple if "tome" in items[i]]})
    else:
        if simple:
            sections.append({"title": "Простые — по цене", "items": simple})
        if built:
            sections.append({"title": "Сборные — по полной стоимости", "items": built})
        if sets:
            sections.append({"title": "Сеты (нужен личный предмет Ex)", "items": sets})
    lines.append("\t{\"title\": %s, \"sections\": %s}," % (json.dumps(title, ensure_ascii=False), gd(sections)))
lines.append("]")
for key, title in CATS:
    print(title, len(tabs[key]), tabs[key])
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "game", "scripts", "data_items.gd")
open(out, "w", encoding="utf-8").write("\n".join(lines) + "\n")
print("items:", len(items), "recipes:", sum(1 for d in items.values() if "recipe" in d))
for k in ("set_akame", "set_esdeath", "lost_relic", "pandora", "yin_yang"):
    print(k, items[k]["price"], "total", total(k))
for k in ("ruby_ring", "orb_fire", "key_set", "black_sword", "rainbow_ring"):
    print(k, items[k])
