function love.conf(t)
  t.identity = "g1r-box-sync-native-" .. tostring(os.getenv("BOX_TEST_RUN"))
  t.version = "11.5"
  t.window.width, t.window.height = 1024, 768
  t.window.title = "Box sync verification"
end
