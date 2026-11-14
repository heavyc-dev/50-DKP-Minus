-- Pack: Seasonal. Dates and times. Data only.
local _, ns = ...

ns:RegisterPack("Seasonal", {
    { id = "since_2004", name = "Since 2004", fine = 50, signal = "LOGIN", when = { month = 11, day = 23 },
      hint = "Log in on the anniversary.", flavor = "Still here. All these years later." },
    { id = "forever_and_a_year", name = "Forever and a Year", fine = 50, signal = "LOGIN", when = { month = 11, day = 4 },
      hint = "Log in on Forever's birthday.", flavor = "You were there for the queues too." },
    { id = "go_see_your_family", name = "Go See Your Family", fine = 50, signal = "LOGIN", when = { month = 12, day = 25 },
      hint = "Log in on a day you shouldn't.", flavor = "They're downstairs. Go." },
    { id = "new_year_same_game", name = "New Year, Same Game", fine = 100, signal = "MINUTE",
      when = { month = 1, day = 1, hour = 0, minute = { max = 5 } },
      hint = "See the year in from Azeroth.", flavor = "Happy New Year. You're in a capital city." },
    { id = "no_plans", name = "No Plans", fine = 50, signal = "MINUTE", distinct = "dateKey", count = 10,
      when = { wday = 6, hour = { min = 20 } },
      hint = "Spend ten Friday nights here.", flavor = "Friday night. Again." },
    { id = "server_shutdown", name = "Server Shutdown", fine = 50, rating = "B", signal = "SHUTDOWN",
      hint = "Be online when they pull the plug.", flavor = "Fifteen minutes. Finish your quest." },
    { id = "refund", name = "Refund", fine = -50, signal = "FEAT_EARNED", when = { month = 4, day = 1 },
      hint = "One day a year, the ledger is feeling generous.", flavor = "April Fools. It's still a fine in spirit." },
})
