barWidget.setGlyph("brightness-up")
barWidget.setText("")
barWidget.setTooltip("Adjust display brightness")

function onClick()
  noctalia.togglePanel("local/studio-brightness:slider")
end
