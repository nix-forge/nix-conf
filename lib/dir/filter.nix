# Predicate combinators for filtering entries
#
# Utilities for building complex filter predicates
_:
let
  inherit (builtins) elem all any;
in
{
  # Standard exclusion filter - excludes entries by name
  #
  # Type: [String] -> Entry -> Bool
  excludeNames = names: entry: !(elem entry.name names);

  # Combine multiple predicates with AND
  #
  # Type: [(Entry -> Bool)] -> Entry -> Bool
  allOf = preds: entry: all (p: p entry) preds;

  # Combine multiple predicates with OR
  #
  # Type: [(Entry -> Bool)] -> Entry -> Bool
  anyOf = preds: entry: any (p: p entry) preds;
}
