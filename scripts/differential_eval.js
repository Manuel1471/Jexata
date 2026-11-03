const fs = require('node:fs');
const [casesPath, referencePath] = process.argv.slice(2);
const jsonata = require(referencePath);
const cases = JSON.parse(fs.readFileSync(casesPath, 'utf8'));

(async () => {
  for (const {name, source, data} of cases) {
    let result;
    try {
      const value = await jsonata(source).evaluate(data);
      result = value === undefined ? {kind: 'undefined'} : {kind: 'value', value};
    } catch (error) {
      result = {kind: 'error', code: error.code || null};
    }
    console.log(JSON.stringify({name, result}));
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
