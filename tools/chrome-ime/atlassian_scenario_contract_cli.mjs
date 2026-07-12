import process from 'node:process';

import { resolveAtlassianScenario } from './atlassian_scenario_contract.mjs';

function parseArguments(argumentsToParse) {
  const names = new Map([
    ['--scenario', 'scenario'],
    ['--word-count', 'wordCount'],
    ['--roman-text', 'romanText'],
    ['--expected-text', 'expectedText'],
  ]);
  const options = {};

  for (let index = 0; index < argumentsToParse.length; index += 2) {
    const key = argumentsToParse[index];
    const name = names.get(key);
    if (!name) {
      throw new Error(`Unexpected argument: ${key}`);
    }
    if (index + 1 >= argumentsToParse.length) {
      throw new Error(`Missing value for ${key}`);
    }
    options[name] = argumentsToParse[index + 1];
  }

  return options;
}

try {
  const scenario = resolveAtlassianScenario(parseArguments(process.argv.slice(2)));
  process.stdout.write(`${JSON.stringify(scenario)}\n`);
} catch (error) {
  process.stderr.write(`${error?.message ?? String(error)}\n`);
  process.exitCode = 2;
}
