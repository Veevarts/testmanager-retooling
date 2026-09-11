// Reproduce la decisión del gate de cadencia PRE vs POST con entradas idénticas.
// PRE  (4458647c~1): interactionsSinceFirstShow % triesBetweenShows
// POST (4458647c)  : interactionsSinceFirstShow % (triesBetweenShows + 1)
const firstEligible = 1;
const gatePRE  = (n, usage) => n != null && n > 0 ? ((usage - firstEligible) % n === 0) : true;
const gatePOST = (n, usage) => n != null && n > 0 ? ((usage - firstEligible) % (n + 1) === 0) : true;

const fmt = (b) => (b ? 'MOSTRAR' : '   -   ');
console.log('Gate de cadencia — misma secuencia de usageCount, codigo PRE-fix vs POST-fix');
console.log('(firstEligibleInteraction = 1, sin triggerType counter)\n');
for (const n of [0, 1, 2]) {
  const pre = [], post = [];
  for (let u = 1; u <= 8; u++) { pre.push(fmt(gatePRE(n, u))); post.push(fmt(gatePOST(n, u))); }
  console.log(`triesBetweenShows = ${n}`);
  console.log(`  PRE  : ${pre.join(' ')}`);
  console.log(`  POST : ${post.join(' ')}`);
  const cadPre = n > 0 ? n : 1, cadPost = n > 0 ? n + 1 : 1;
  console.log(`  cadencia efectiva: PRE ${cadPre} -> POST ${cadPost}${n === 1 ? '   <-- EL DEFECTO REPORTADO' : ''}\n`);
}
