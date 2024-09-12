-- Taken from this helpful SO answer: https://stackoverflow.com/a/27914619
local function compose(...)
  local fnchain = ...
  local function recurse(i, ...)
    if i == #fnchain then
      return fnchain[i](...)
    end
    return recurse(i + 1, fnchain[i](...))
  end
  return function(...) return recurse(1, ...) end
end

return {
  compose = compose
}
