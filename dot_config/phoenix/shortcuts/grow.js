
/* GROW */

const growOrShrink = [
  ['up', HYPER_2, [
    [0, - GROW_AMOUNT, 0, GROW_AMOUNT],
    [0, 0, 0, - GROW_AMOUNT]
  ]],
  ['right', HYPER_2, [
    [0, 0, GROW_AMOUNT, 0],
    [GROW_AMOUNT, 0, - GROW_AMOUNT, 0]
  ]],
  ['down', HYPER_2, [
    [0, 0, 0, GROW_AMOUNT],
    [0, GROW_AMOUNT, 0, - GROW_AMOUNT],
  ]],
  ['left', HYPER_2, [
    [- GROW_AMOUNT, 0, GROW_AMOUNT, 0],
    [0, 0, - GROW_AMOUNT, 0]
  ]]
];

setKeysHandler ( growOrShrinkFrame, growOrShrink, false );
