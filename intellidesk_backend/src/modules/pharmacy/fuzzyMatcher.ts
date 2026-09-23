import { RX_NORM_DATASET, NORMALIZED_DRUG_INDEX } from './rxNormDataset.js';
import { RxNormConcept } from './types.js';

export interface FuzzyMatchResult {
  concept: RxNormConcept | null;
  matchedTerm: string;
  activeIngredient: string;
  brandName: string;
  confidence: number;
  isVerified: boolean;
}

/**
 * Computes Levenshtein edit distance between two strings.
 */
export function levenshteinDistance(a: string, b: string): number {
  const an = a.length;
  const bn = b.length;
  if (an === 0) return bn;
  if (bn === 0) return an;

  const matrix: number[][] = [];
  for (let i = 0; i <= bn; i++) {
    matrix[i] = [i];
  }
  for (let j = 0; j <= an; j++) {
    matrix[0][j] = j;
  }

  for (let i = 1; i <= bn; i++) {
    for (let j = 1; j <= an; j++) {
      if (b.charAt(i - 1) === a.charAt(j - 1)) {
        matrix[i][j] = matrix[i - 1][j - 1];
      } else {
        matrix[i][j] = Math.min(
          matrix[i - 1][j - 1] + 1, // substitution
          matrix[i][j - 1] + 1,     // insertion
          matrix[i - 1][j] + 1      // deletion
        );
      }
    }
  }

  return matrix[bn][an];
}

/**
 * Computes Jaro similarity.
 */
function jaroSimilarity(s1: string, s2: string): number {
  if (s1 === s2) return 1.0;
  const l1 = s1.length;
  const l2 = s2.length;
  if (l1 === 0 || l2 === 0) return 0.0;

  const matchDistance = Math.floor(Math.max(l1, l2) / 2) - 1;
  const s1Matches = new Array(l1).fill(false);
  const s2Matches = new Array(l2).fill(false);

  let matches = 0;
  for (let i = 0; i < l1; i++) {
    const start = Math.max(0, i - matchDistance);
    const end = Math.min(i + matchDistance + 1, l2);
    for (let j = start; j < end; j++) {
      if (s2Matches[j]) continue;
      if (s1.charAt(i) !== s2.charAt(j)) continue;
      s1Matches[i] = true;
      s2Matches[j] = true;
      matches++;
      break;
    }
  }

  if (matches === 0) return 0.0;

  let transpositions = 0;
  let k = 0;
  for (let i = 0; i < l1; i++) {
    if (!s1Matches[i]) continue;
    while (!s2Matches[k]) k++;
    if (s1.charAt(i) !== s2.charAt(k)) transpositions++;
    k++;
  }

  return (matches / l1 + matches / l2 + (matches - transpositions / 2) / matches) / 3;
}

/**
 * Computes Jaro-Winkler similarity score [0.0, 1.0].
 */
export function jaroWinklerSimilarity(s1: string, s2: string, prefixScale = 0.1): number {
  const jaro = jaroSimilarity(s1, s2);
  let prefix = 0;
  const maxPrefix = Math.min(4, Math.min(s1.length, s2.length));
  for (let i = 0; i < maxPrefix; i++) {
    if (s1.charAt(i) === s2.charAt(i)) prefix++;
    else break;
  }
  return jaro + prefix * prefixScale * (1 - jaro);
}

/**
 * Combined hybrid similarity metric: max of normalized Levenshtein and Jaro-Winkler.
 */
export function calculateSimilarity(s1: string, s2: string): number {
  const norm1 = s1.trim().toLowerCase();
  const norm2 = s2.trim().toLowerCase();
  if (norm1 === norm2) return 1.0;
  if (!norm1 || !norm2) return 0.0;

  const maxLen = Math.max(norm1.length, norm2.length);
  const levDist = levenshteinDistance(norm1, norm2);
  const levSim = Math.max(0, 1.0 - levDist / maxLen);

  const jwSim = jaroWinklerSimilarity(norm1, norm2);
  return Math.max(levSim, jwSim);
}

/**
 * Technical Guardrail 1: Zero-Crash Fuzzy Match Bounds
 * Resolves handwriting or OCR typos against RxNorm terms.
 * Requires threshold >= 0.75. If no candidate reaches threshold,
 * safely returns unverified raw string without throwing an exception.
 */
export function findBestRxNormMatch(rawCandidate: string, threshold = 0.75): FuzzyMatchResult {
  const safeQuery = (rawCandidate || '').trim();
  if (!safeQuery) {
    return {
      concept: null,
      matchedTerm: '',
      activeIngredient: '',
      brandName: '',
      confidence: 0.0,
      isVerified: false
    };
  }

  const queryLower = safeQuery.toLowerCase();

  // 1. Direct O(1) hash table lookup
  const exact = NORMALIZED_DRUG_INDEX.get(queryLower);
  if (exact) {
    return {
      concept: exact,
      matchedTerm: safeQuery,
      activeIngredient: exact.activeIngredient,
      brandName: exact.brandAliases[0] || exact.activeIngredient,
      confidence: 1.0,
      isVerified: true
    };
  }

  // 2. Fuzzy scan over dataset terms
  let bestScore = 0.0;
  let bestConcept: RxNormConcept | null = null;
  let bestTerm = '';

  for (const concept of RX_NORM_DATASET) {
    // Check active ingredient
    const ingScore = calculateSimilarity(queryLower, concept.activeIngredient.toLowerCase());
    if (ingScore > bestScore) {
      bestScore = ingScore;
      bestConcept = concept;
      bestTerm = concept.activeIngredient;
    }

    // Check brand aliases
    for (const brand of concept.brandAliases) {
      const brandScore = calculateSimilarity(queryLower, brand.toLowerCase());
      if (brandScore > bestScore) {
        bestScore = brandScore;
        bestConcept = concept;
        bestTerm = brand;
      }
    }
  }

  if (bestScore >= threshold && bestConcept) {
    return {
      concept: bestConcept,
      matchedTerm: bestTerm,
      activeIngredient: bestConcept.activeIngredient,
      brandName: bestConcept.brandAliases[0] || bestConcept.activeIngredient,
      confidence: Math.round(bestScore * 100) / 100,
      isVerified: true
    };
  }

  // Guardrail 1: Unverified fallback retention with 0 crash
  return {
    concept: null,
    matchedTerm: safeQuery,
    activeIngredient: safeQuery,
    brandName: safeQuery,
    confidence: Math.round(bestScore * 100) / 100,
    isVerified: false
  };
}
