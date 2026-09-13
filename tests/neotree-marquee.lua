local marquee = require("neotree_marquee")

assert(marquee._window("abcdefgh", 5, 0) == "abcde")
assert(marquee._window("abcdefgh", 5, 2) == "cdefg")
assert(marquee._window("abcdefgh", 5, 8) == "   ab")
assert(vim.fn.strdisplaywidth(marquee._window("abcdefghi", 6, 7)) == 6)
assert(vim.fn.strdisplaywidth(marquee._window("한글파일이름", 6, 1)) == 6)
