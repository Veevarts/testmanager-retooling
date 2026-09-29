#!/bin/zsh
# Antes/despues con el WorkspaceService real: pre = 1b8f067a (sin #410), post = a2ceb94b. Misma ventana SQL (36 meses).
S=${QA_SCRATCH:?ruta del scratchpad}
H=$S/im-1245/harness2
SPEC=src/csm/workspace/qa-im1245-harness.spec.ts
for side in pre post; do
  [ $side = pre ] && T=$S/im-1245/wt-pre || T=$S/im-1207/be
  cp $S/im-1245/harness/qa-im1245-harness.spec.ts $T/$SPEC
  for d in d1-dev d2-legacy d3-gap; do
    ( cd $T && QA_MODE=post QA_IN=$S/im-1245/harness/$d.json QA_OUT=$H/out-$d-$side.json QA_CALLS="$(cat $H/calls.json)" fnm exec --using=20 npx jest --ci $SPEC > $H/log-$d-$side.txt 2>&1; echo "exit=$?" >> $H/log-$d-$side.txt )
  done
  ( cd $T && /usr/bin/time -l env QA_MODE=post QA_IN=$S/im-1245/harness/d1-dev.json QA_OUT=$H/out-x1-$side.json QA_CALLS="$(cat $H/calls-x1.json)" fnm exec --using=20 npx jest --ci $SPEC > $H/log-x1-$side.txt 2>&1; echo "exit=$?" >> $H/log-x1-$side.txt )
  if [ $side = post ]; then
    ( cd $T && /usr/bin/time -l env QA_MODE=post QA_IN=$S/im-1245/harness/d1-dev.json QA_OUT=$H/out-x2-$side.json QA_CALLS="$(cat $H/calls-x2.json)" fnm exec --using=20 npx jest --ci $SPEC > $H/log-x2-$side.txt 2>&1; echo "exit=$?" >> $H/log-x2-$side.txt )
  fi
  rm -f $T/$SPEC
done
echo DONE > $H/done
