-- Lesson pages: put a visible link to the slide version at the top of the page.
-- Quarto's own "Also as" link sits in the right margin, which phones hide.
-- The slides file name comes from the lesson's own revealjs output-file.
function Pandoc(doc)
  if not quarto.doc.is_format("html") or quarto.doc.is_format("revealjs") then
    return doc
  end
  local stem = pandoc.path.split_extension(pandoc.path.filename(quarto.doc.input_file))
  local href = stem .. "-slides.html"
  local link = pandoc.Div(
    { pandoc.Para({ pandoc.Link({ pandoc.Str("Open the slides for this module") }, href) }) },
    pandoc.Attr("", { "slides-link" })
  )
  table.insert(doc.blocks, 1, link)
  return doc
end
