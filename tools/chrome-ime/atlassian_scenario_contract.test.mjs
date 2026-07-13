import assert from 'node:assert/strict';
import test from 'node:test';

import {
  expectedDocumentState,
  resolveAtlassianScenario,
} from './atlassian_scenario_contract.mjs';

test('resolves the wrapper defaults to one 안녕하세요 scenario with word count three', () => {
  for (const options of [undefined, { scenario: '', wordCount: '' }]) {
    const scenario = resolveAtlassianScenario(options);
    assert.equal(scenario.scenario, 'annyeonghaseyo');
    assert.equal(scenario.word_count, 3);
    assert.equal(scenario.expected_text, '안녕하세요');
  }

  const words = resolveAtlassianScenario({ scenario: 'annyeonghaseyo-words' });
  assert.equal(words.word_count, 3);
  assert.equal(words.expected_text, '안녕하세요 안녕하세요 안녕하세요');
});

test('resolves every fixed Confluence scenario to its exact document delta', () => {
  const expectedByScenario = new Map([
    ['annyeonghaseyo', '안녕하세요'],
    ['annyeong-space-backspace', '안녕'],
    ['foo-bar-annyeong-space-backspace', 'foo안녕 bar'],
    ['roman-foo-bar', 'foo bar foo bar'],
  ]);

  for (const [scenario, expectedText] of expectedByScenario) {
    assert.equal(resolveAtlassianScenario({ scenario }).expected_text, expectedText);
  }
});

test('resolves the multi-word output without a trailing separator', () => {
  for (const [wordCount, expectedText] of [
    [1, '안녕하세요'],
    [3, '안녕하세요 안녕하세요 안녕하세요'],
    [5, '안녕하세요 안녕하세요 안녕하세요 안녕하세요 안녕하세요'],
  ]) {
    const scenario = resolveAtlassianScenario({
      scenario: 'annyeonghaseyo-words',
      wordCount,
    });
    assert.equal(scenario.word_count, wordCount);
    assert.equal(scenario.expected_text, expectedText);
    assert.equal(scenario.expected_text.endsWith(' '), false);
  }
});

test('uses custom Roman text as the default exact output', () => {
  const scenario = resolveAtlassianScenario({
    scenario: 'roman-text',
    romanText: 'qwx foo zyx qwx',
  });

  assert.equal(scenario.roman_text, 'qwx foo zyx qwx');
  assert.equal(scenario.expected_text, 'qwx foo zyx qwx');
});

test('keeps an explicit expected override separate and preserves whitespace', () => {
  const scenario = resolveAtlassianScenario({
    scenario: 'roman-text',
    romanText: 'foo bar',
    expectedText: ' foo bar ',
  });

  assert.equal(scenario.roman_text, 'foo bar');
  assert.equal(scenario.expected_text, ' foo bar ');
});

test('rejects missing Roman input, unknown scenarios, and invalid word counts', () => {
  assert.throws(
    () => resolveAtlassianScenario({ scenario: 'roman-text' }),
    /HISLE_ATLASSIAN_ROMAN_TEXT is required/,
  );
  assert.throws(
    () => resolveAtlassianScenario({ scenario: 'unknown' }),
    /Unsupported HISLE_ATLASSIAN_SCENARIO/,
  );
  for (const wordCount of ['abc', '1.5', '0', '-1']) {
    assert.throws(
      () => resolveAtlassianScenario({ scenario: 'annyeonghaseyo-words', wordCount }),
      /HISLE_ATLASSIAN_WORD_COUNT must be a positive integer/,
    );
  }
});

test('matches only the exact document delta at the captured caret', () => {
  const exact = expectedDocumentState({
    initialRangeText: 'foo bar',
    initialCaretOffset: 3,
    expectedText: '안녕',
    actualRangeText: 'foo안녕 bar',
  });
  assert.deepEqual(exact, {
    expected_full_text: 'foo안녕 bar',
    contains_expected_text: true,
    matches_expected_full_text: true,
  });

  for (const actualRangeText of [
    'foo안녕 bar ',
    '안녕foo bar',
    'foo bar안녕',
  ]) {
    const mismatch = expectedDocumentState({
      initialRangeText: 'foo bar',
      initialCaretOffset: 3,
      expectedText: '안녕',
      actualRangeText,
    });
    assert.equal(mismatch.contains_expected_text, true);
    assert.equal(mismatch.matches_expected_full_text, false);
  }
});

test('rejects one word for an N-word scenario and text that already existed', () => {
  const words = resolveAtlassianScenario({
    scenario: 'annyeonghaseyo-words',
    wordCount: 3,
  });
  const oneWord = expectedDocumentState({
    initialRangeText: '',
    initialCaretOffset: 0,
    expectedText: words.expected_text,
    actualRangeText: '안녕하세요',
  });
  assert.equal(oneWord.matches_expected_full_text, false);

  const preexisting = expectedDocumentState({
    initialRangeText: '안녕하세요',
    initialCaretOffset: 5,
    expectedText: '안녕하세요',
    actualRangeText: '안녕하세요',
  });
  assert.equal(preexisting.contains_expected_text, true);
  assert.equal(preexisting.matches_expected_full_text, false);
});
