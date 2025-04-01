-- slice a word to individual slices. "my_cool_word" -> { "my", "cool", "word" }
function get_word_slices(name)
  local slices = {}
  local current_word = ""
  local last_character_uppercase = true

  for i = 1, #name do
    local character = name:sub(i, i)

    if character == "_" or character == "-" then
      if current_word ~= "" then
        table.insert(slices, current_word)
        current_word = ""
      end

      last_character_uppercase = false
    elseif string.upper(character) == character then

      if last_character_uppercase or current_word == "" then
        current_word = current_word .. string.lower(character)
      else
        table.insert(slices, current_word)
        current_word = string.lower(character)
      end

      last_character_uppercase = true
    else
      current_word = current_word .. character
      last_character_uppercase = false
    end
  end

  if current_word ~= "" then
    table.insert(slices, current_word)
  end

  return slices
end

-- e.g. my_cool_word
function snake_case(slices)
  local word = ""

  for index, slice in ipairs(slices) do
    if index > 1 then
      word = word .. "_"
    end

    word = word .. slice
  end

  return word
end

-- e.g. my-cool-word
function kebab_case(slices)
  local word = ""

  for index, slice in ipairs(slices) do
    if index > 1 then
      word = word .. "-"
    end

    word = word .. slice
  end

  return word
end

-- e.g. myCoolWord
function camel_case(slices)
  local word = ""

  for index, slice in ipairs(slices) do
    if index == 1 then
      word = word .. slice
    else
      word = word .. string.upper(string.sub(slice, 1, 1))
      word = word .. string.sub(slice, 2, -1)
    end
  end

  return word
end

-- e.g. MyCoolWord
function pascal_case(slices)
  local word = ""

  for _, slice in ipairs(slices) do
    word = word .. string.upper(string.sub(slice, 1, 1))
    word = word .. string.sub(slice, 2, -1)
  end

  return word
end

-- e.g. MY_COOL_WORD
function macro_case(slices)
  local word = ""

  for index, slice in ipairs(slices) do
    if index > 1 then
      word = word .. "_"
    end

    word = word .. string.upper(slice)
  end

  return word
end

-- lookup table for all cases that are suppored out of the box
return {
  ["snake"] = snake_case,
  ["camel"] = camel_case,
  ["pascal"] = pascal_case,
  ["kebab"] = kebab_case,
  ["macro"] = macro_case,
}
