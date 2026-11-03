// Run with node scripts/benchmark_vs_jsonata.js fixture.json /path/to/jsonata/src/jsonata.js.
const fs = require('node:fs');
const [fixturePath, referencePath] = process.argv.slice(2);
const {data, cases} = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
const jsonata = require(referencePath);

(async () => {
  let floorStart = process.hrtime.bigint();
  for (let index = 0; index < 10000; index++) await Promise.resolve();
  floorStart = process.hrtime.bigint();
  for (let index = 0; index < 10000; index++) await Promise.resolve();
  console.log(JSON.stringify({case: 'promise_floor', ns_per_op: Number(process.hrtime.bigint() - floorStart) / 10000}));

  for (const {name, source, mode, iterations} of cases) {
    const compiled = jsonata(source);
    const operation = mode === 'compile'
      ? () => jsonata(source)
      : () => compiled.evaluate(data);
    const result = mode === 'compile' ? 0 : await operation();
    for (let index = 0; index < 3; index++) {
      if (mode === 'compile') operation();
      else await operation();
    }
    const started = process.hrtime.bigint();
    for (let index = 0; index < iterations; index++) {
      if (mode === 'compile') operation();
      else await operation();
    }
    const elapsed = process.hrtime.bigint() - started;
    console.log(JSON.stringify({
      case: name,
      mode,
      iterations,
      ns_per_op: Number(elapsed) / iterations,
      result
    }));
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
