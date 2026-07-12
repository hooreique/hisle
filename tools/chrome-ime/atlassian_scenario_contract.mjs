const defaultScenario = 'annyeonghaseyo';
const defaultWordCount = 3;

function configuredText(value) {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function resolveWordCount(value) {
  if (value == null || value === '') {
    return defaultWordCount;
  }

  const wordCount = typeof value === 'number' ? value : Number(value);
  if (!Number.isSafeInteger(wordCount) || wordCount < 1) {
    throw new Error('HISLE_ATLASSIAN_WORD_COUNT must be a positive integer.');
  }
  return wordCount;
}

export function resolveAtlassianScenario({
  scenario = defaultScenario,
  wordCount,
  romanText,
  expectedText,
} = {}) {
  const resolvedScenario = configuredText(scenario) ?? defaultScenario;
  const resolvedWordCount = resolveWordCount(wordCount);
  const configuredRomanText = configuredText(romanText);
  let documentDelta;
  let resolvedRomanText = null;

  switch (resolvedScenario) {
    case 'annyeonghaseyo':
      documentDelta = '안녕하세요';
      break;
    case 'annyeonghaseyo-words':
      documentDelta = Array(resolvedWordCount).fill('안녕하세요').join(' ');
      break;
    case 'annyeong-space-backspace':
      documentDelta = '안녕';
      break;
    case 'foo-bar-annyeong-space-backspace':
      documentDelta = 'foo안녕 bar';
      break;
    case 'roman-foo-bar':
      documentDelta = 'foo bar foo bar';
      break;
    case 'roman-text':
      if (configuredRomanText == null) {
        throw new Error('HISLE_ATLASSIAN_ROMAN_TEXT is required for the roman-text scenario.');
      }
      resolvedRomanText = configuredRomanText;
      documentDelta = resolvedRomanText;
      break;
    default:
      throw new Error(`Unsupported HISLE_ATLASSIAN_SCENARIO: ${resolvedScenario}`);
  }

  return {
    scenario: resolvedScenario,
    word_count: resolvedWordCount,
    roman_text: resolvedRomanText,
    expected_text: configuredText(expectedText) ?? documentDelta,
  };
}

export function expectedDocumentState({
  initialRangeText,
  initialCaretOffset,
  expectedText,
  actualRangeText,
}) {
  const hasValidInputs = typeof initialRangeText === 'string' &&
    Number.isInteger(initialCaretOffset) &&
    initialCaretOffset >= 0 &&
    initialCaretOffset <= initialRangeText.length &&
    typeof expectedText === 'string' &&
    typeof actualRangeText === 'string';
  const expectedFullText = hasValidInputs
    ? initialRangeText.slice(0, initialCaretOffset) +
      expectedText +
      initialRangeText.slice(initialCaretOffset)
    : null;

  return {
    expected_full_text: expectedFullText,
    contains_expected_text: typeof actualRangeText === 'string' &&
      typeof expectedText === 'string' &&
      actualRangeText.includes(expectedText),
    matches_expected_full_text: expectedFullText != null && actualRangeText === expectedFullText,
  };
}
