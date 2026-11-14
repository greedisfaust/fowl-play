path = r'C:\Users\Faust\Desktop\fowl-play\dev-fowl-play\player\player.gd'
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

# Replace all non-ASCII with ASCII equivalents
replacements = {
    chr(0x2018): "'",   # left single quote
    chr(0x2019): "'",   # right single quote
    chr(0x201c): '"',   # left double quote
    chr(0x201d): '"',   # right double quote
    chr(0x2192): '->',  # rightwards arrow
    chr(0x2014): '-',   # em dash
    chr(0x2013): '-',   # en dash
}
for old, new in replacements.items():
    text = text.replace(old, new)

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)

# Verify no non-ASCII remains
with open(path, 'rb') as f:
    data = f.read()
non_ascii = [(i, b) for i, b in enumerate(data) if b > 127]
print('Non-ASCII bytes remaining:', len(non_ascii))
