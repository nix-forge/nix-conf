[.. | objects | (."$ref"?, ."$dynamicRef"?, ."$recursiveRef"?) | select(. != null)]
  | all(type == "string" and startswith("#"))
