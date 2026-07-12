-- 同期ステートシステム
-- calculateTickは、現在の入力と、前回のstate出力を受けとり、stateとならない出力とstateとなる出力の2つを返す
-- 一般入出力はfloat前提、state入出力はinteger前提
-- 外部で1tickだけ遅れる形でフィードバック入力されるよう組まれている。同期によって強制的に値が更新されると内部値を破棄して再計算する
-- 入力 N1-8: 現在の入力, N9-16: 1tick遅れた"現在入力", N17-24: 2tick遅れた出力fb, N25-32: stateのフィードバック
-- 出力 N1-8: 2tick遅れた出力, N9-16: 2tick遅れたstate出力, N17-24: このtickの出力, N25-32: このtickのstate出力

function i2f(n)
  local x = ('f'):unpack(('I4'):pack(n & 0xFFFFFFFF))
  return x
end

function f2i(x)
  local n = ('I4'):unpack(('f'):pack(x))
  return n
end

s1 = {0,0,0,0,0,0,0,0} -- 1tick前. integerで保存
s2 = {0,0,0,0,0,0,0,0} -- 2tick前. integerで保存

function onTick()
  local i0, i1, o2_fb, s2_fb = {}, {}, {}, {}
  local o0, s0, o1
  for i = 1, 8 do
    i0[i] = input.getNumber(i)
    i1[i] = input.getNumber(i + 8)
    o2_fb[i] = input.getNumber(i + 16)
    s2_fb[i] = f2i(input.getNumber(i + 24))
  end

  -- 内部で保持している2tick前ステートと、フィードバック入力が一致しているか確認
  local eq = true
  for i = 1, 8 do
    eq = eq and (s2[i] == s2_fb[i])
  end

  -- もし不一致ならば、入力を正として1tick前のステートを再計算
  if not eq then
    o1, s1 = calculateTick(i1, s2_fb)
  end

  -- いまのステートを計算
  o0, s0 = calculateTick(i0, s1)

  for i = 1, 8 do
    output.setNumber(i, o2_fb[i]) -- 2tick前
    output.setNumber(i + 8, i2f(s2_fb[i])) -- 2tick前
    output.setNumber(i + 16, o0[i]) -- fb用
    output.setNumber(i + 24, i2f(s0[i])) -- fb用
  end

  -- ステートを次tick用に順繰り
  s2 = s1
  s1 = s0
end
