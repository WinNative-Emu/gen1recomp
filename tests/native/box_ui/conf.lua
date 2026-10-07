function love.conf(t)
  t.identity = "g1r-box-ui-native-" .. assert(os.getenv("BOX_UI_RUN"))
  t.window.title = "Box UI verification"
  t.window.width, t.window.height = 1360, 860
  t.window.resizable = true
end
