local locale = dofile('src/AwakeningCrystalConverterUI/Scripts/locale.lua')
assert(#locale.languages == 17)
local elements = {'Electric','Fire','Water','Grass','Ground','Ice','Dragon','Dark','Neutral'}
for _, language in ipairs(locale.languages) do
    assert(locale.resolve(language) == language)
    local text = locale.entry(language)
    for _, id in ipairs(elements) do assert(type(text.elements[id]) == 'string' and #text.elements[id] > 0) end
    local exchange = locale.format(language, 'spend_receive', 'SOURCE', 'TARGET')
    assert(exchange:find('SOURCE', 1, true) and exchange:find('TARGET', 1, true))
    assert(not exchange:find('{source}', 1, true) and not exchange:find('{target}', 1, true))
    assert(text.description:find('36', 1, true) and text.description:find('576', 1, true))
end
assert(locale.resolve('zh-TW') == 'zh-Hant')
assert(locale.resolve('zh_CN') == 'zh-Hans')
assert(locale.resolve('es-ES') == 'es')
assert(locale.resolve('unknown') == 'en')
print('PASS: 17 locales, nine elements, exchange placeholders, aliases and fallback')
