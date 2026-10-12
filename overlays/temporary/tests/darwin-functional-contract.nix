# Pure regression for narrowing the combined package's test dependency graph.
let
  lib = {
    getName = package: package.name;
    findSingle =
      predicate: missing: multiple: values:
      let
        matches = builtins.filter predicate values;
      in
      if builtins.length matches == 1 then
        builtins.head matches
      else if matches == [ ] then
        missing
      else
        multiple;
  };
  functional =
    let
      self = {
        name = "nix-functional-tests";
        doCheck = true;
        mesonCheckFlags = [ "--print-errorlogs" ];
        overrideAttrs = transform: self // transform self;
      };
    in
    self;
  units = builtins.genList (index: {
    name = "unit-${toString index}";
    drvPath = "unit-${toString index}";
  }) 5;
  package =
    checks:
    let
      self = {
        doCheck = true;
        buildInputs = checks;
        override =
          arguments:
          package (
            map (
              check: if check.name == "nix-functional-tests" then arguments.nix-functional-tests else check
            ) checks
          );
        overrideAttrs = transform: self // transform self;
      };
    in
    self;
  fix = import ../determinate-darwin-tests.nix { inherit lib; };
  original = package (units ++ [ functional ]);
  repaired = fix.apply original;
  accepts =
    candidate: (builtins.tryEval (builtins.deepSeq (fix.apply candidate).buildInputs true)).success;
  repairedUnits = builtins.filter (check: check.name != "nix-functional-tests") repaired.buildInputs;
  repairedFunctional = builtins.head (
    builtins.filter (check: check.name == "nix-functional-tests") repaired.buildInputs
  );
in
assert !(original ? checkInputs) && !(repaired ? checkInputs);
assert repaired.doCheck;
assert repairedUnits == units;
assert builtins.length repaired.buildInputs == 6;
assert repairedFunctional.doCheck;
assert
  repairedFunctional.mesonCheckFlags == [
    "--print-errorlogs"
    "--exclude"
    "sentry"
  ];
assert !accepts (package units);
assert
  !accepts (
    package (
      units
      ++ [
        functional
        functional
      ]
    )
  );
assert !accepts (original // { doCheck = false; });
assert !accepts (package (units ++ [ (functional // { doCheck = false; }) ]));
assert
  !accepts (
    package (
      units
      ++ [
        functional
        { name = "unexpected-input"; }
      ]
    )
  );
true
