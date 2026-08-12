local _, ns = ...
ns.CHAINGUIDE_OVERLAYS = ns.CHAINGUIDE_OVERLAYS or {}

    ns.CHAINGUIDE_OVERLAYS[6050] = {
        layout = {
            [98541] = { x = 1, y = 0  },
            [92897] = { x = 1, y = 1  },
            [92895] = { x = 1, y = 2  },
            [92899] = { x = 1, y = 3  },
            [92900] = { x = 1, y = 4  },
            [92901] = { x = 1, y = 5  },
            [92904] = { x = 1, y = 6  },
            [92907] = { x = 1, y = 7  },
            [92955] = { x = 1, y = 8  },
            [92957] = { x = 0, y = 9  },
            [92958] = { x = 2, y = 9  },
            [92952] = { x = 1, y = 10 },
            [92953] = { x = 0, y = 11 },
            [92951] = { x = 2, y = 11 },
            [92954] = { x = 1, y = 12 },
            [93010] = { x = 1, y = 13 },
            [93011] = { x = 1, y = 14 },
            [93012] = { x = 1, y = 15 },
        },
        connections = {
            [92897] = { 98541 },
            [92895] = { 92897 },
            [92899] = { 92895 },
            [92900] = { 92899 },
            [92901] = { 92900 },
            [92904] = { 92901 },
            [92907] = { 92904 },
            [92955] = { 92907 },
            [92957] = { 92955 },
            [92958] = { 92955 },
            [92952] = { 92957, 92958 },
            [92953] = { 92952 },
            [92951] = { 92952 },
            [92954] = { 92953, 92951 },
            [93010] = { 92954 },
            [93011] = { 93010 },
            [93012] = { 93011 },
        },
    }

ns.CURATED_QUEST_NAMES = ns.CURATED_QUEST_NAMES or {}
local names = ns.CURATED_QUEST_NAMES
names[92897] = "The Preparations Are Complete"
names[92895] = "Hagar's Invitation"
names[92899] = "History Lesson"
names[92900] = "A Favor for Kinduru"
names[92901] = "Revisionist History"
names[92904] = "Return to Zul'Aman"
names[92907] = "Amani Answers"
names[92955] = "The Tablets of Numazon"
names[92957] = "There's the Rub"
names[92958] = "Brain Drain"
names[92952] = "Mission to Maisara"
names[92953] = "Memories of Malacrass"
names[92951] = "Digging Deeper"
names[92954] = "Maisara Caverns: Master of Souls"
names[93010] = "The Serpent Shrine"
names[93011] = "Legacy of the Amani"
names[93012] = "Dead End"
