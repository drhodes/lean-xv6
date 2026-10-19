import «LeanXv6»

def main : IO Unit := do
  IO.println "# ============================================================================"
  IO.println "# Lean 4 Generated RV64 Assembly for xv6 Boot"
  IO.println "# ============================================================================"
  let asmCode := LeanXv6.Boot.bootAssembly
  IO.println asmCode
  IO.FS.createDirAll "build"
  IO.FS.writeFile "build/boot.S" asmCode
  IO.println "# Generated build/boot.S successfully."
