--[[
generated: show the saved output of a real command, made by _scripts/generate.py.

  {{< generated name="microcpipe-dryrun" >}}
  {{< generated name="microcpipe-dryrun" lines="1-25" >}}
  {{< generated name="ttpipe-dryrun" head="20" >}}
  {{< generated name="ttpipe-dryrun" tail="8" >}}
  {{< generated name="microcpipe-rulegraph" >}}        (a graph: drawn as an image)
  {{< generated name="microcpipe-rulegraph" as="code" >}}  (the dot text instead)

Looks for _generated/<name>.svg (with .dot beside it), then .dot, then .txt.
Other arguments:
  command   "false" to hide the "$ command" label above a text block
  alt       alt text for a graph (default: "Graph of <name>")
  width     image width for a graph, e.g. "80%"
If nothing is there yet, a short note says how to produce it.
]]

local manifest_cache

-- Quarto adds the filename bar while parsing the document, before shortcodes
-- run, so build the same markup it uses (DecoratedCodeBlock html renderer).
local function with_filename(code, filename)
  if not filename or not quarto.doc.is_format("html") then return code end
  local bar = pandoc.Div({ pandoc.Plain({
    pandoc.RawInline("html", "<pre>"),
    pandoc.Strong({ pandoc.Str(filename) }),
    pandoc.RawInline("html", "</pre>"),
  }) }, pandoc.Attr("", { "code-with-filename-file" }))
  return pandoc.Div({ bar, code }, pandoc.Attr("", { "code-with-filename" }))
end

local function str(v)
  if v == nil then return nil end
  local s = pandoc.utils.stringify(v)
  if s == "" then return nil end
  return s
end

local function project_dir()
  if quarto.project and quarto.project.directory then
    return quarto.project.directory
  end
  return pandoc.system.get_working_directory()
end

local function offset()
  local off = quarto.project and quarto.project.offset
  if off == nil or off == "" then return "." end
  return off
end

local function read_file(path)
  local fh = io.open(path, "r")
  if not fh then return nil end
  local s = fh:read("*a")
  fh:close()
  return s
end

local function manifest()
  if manifest_cache ~= nil then return manifest_cache end
  manifest_cache = {}
  local s = read_file(project_dir() .. "/_generated/manifest.json")
  if s then
    local ok, data = pcall(quarto.json.decode, s)
    if ok and type(data) == "table" then manifest_cache = data end
  end
  return manifest_cache
end

local function split_lines(s)
  local out = {}
  for line in (s .. "\n"):gmatch("(.-)\n") do out[#out + 1] = line end
  while #out > 0 and out[#out] == "" do table.remove(out) end
  return out
end

local function select_lines(lines, kwargs)
  local spec = str(kwargs["lines"])
  local head = tonumber(str(kwargs["head"]) or "")
  local tail = tonumber(str(kwargs["tail"]) or "")
  local a, b = 1, #lines
  if spec then
    local x, y = spec:match("^%s*(%d+)%s*%-%s*(%d*)%s*$")
    if not x then x = spec:match("^%s*(%d+)%s*$"); y = x end
    if x then
      a = tonumber(x)
      b = (y == nil or y == "") and #lines or tonumber(y)
    end
  elseif head then
    b = math.min(head, #lines)
  elseif tail then
    a = math.max(1, #lines - tail + 1)
  end
  local out = {}
  if a > 1 then out[#out + 1] = "..." end
  for i = a, math.min(b, #lines) do out[#out + 1] = lines[i] end
  if b < #lines then out[#out + 1] = "..." end
  return out
end

local function missing(name)
  quarto.log.warning("generated: no output named '" .. name .. "' in _generated/")
  return quarto.Callout({
    type = "note",
    title = "Output not here yet",
    appearance = "simple",
    content = { pandoc.Para({
      pandoc.Str("This output ("), pandoc.Code(name),
      pandoc.Str(") is made from the course data. Once "), pandoc.Code("data/"),
      pandoc.Str(" is in place, run "), pandoc.Code("quarto render"),
      pandoc.Str(" and it appears here. Until then, run the command yourself and compare."),
    }) },
  })
end

local function generated(args, kwargs, meta)
  local name = str(kwargs["name"]) or (args[1] and str(args[1]))
  if not name then
    return quarto.Callout({ type = "warning", title = "generated: no name",
      content = { pandoc.Para({ pandoc.Str('Use {{< generated name="..." >}}.') }) } })
  end
  local root = project_dir() .. "/_generated/"
  local entry = manifest()[name] or {}
  local as_code = str(kwargs["as"]) == "code"

  local svg = read_file(root .. name .. ".svg")
  if svg and not as_code then
    local alt = str(kwargs["alt"]) or ("Graph of " .. name)
    local attrs = {}
    if str(kwargs["width"]) then attrs[#attrs + 1] = { "width", str(kwargs["width"]) } end
    local img = pandoc.Image({ pandoc.Str(alt) }, offset() .. "/_generated/" .. name .. ".svg", "",
      pandoc.Attr("", { "generated-graph" }, attrs))
    return pandoc.Div({ pandoc.Plain({ img }) }, pandoc.Attr("", { "generated", "generated-graph-wrap" }))
  end

  local text, lang = read_file(root .. name .. ".dot"), "dot"
  if not text then text, lang = read_file(root .. name .. ".txt"), "default" end
  if not text then return missing(name) end

  local lines = select_lines(split_lines(text), kwargs)
  local label
  if entry.command and str(kwargs["command"]) ~= "false" then label = "$ " .. entry.command end
  local code = with_filename(pandoc.CodeBlock(table.concat(lines, "\n"), pandoc.Attr("", { lang })), label)
  return pandoc.Div({ code }, pandoc.Attr("", { "generated", "generated-output" }, { { "data-name", name } }))
end

return {
  ["generated"] = generated,
}
