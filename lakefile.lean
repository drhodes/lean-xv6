import Lake
open Lake DSL

package «lean-xv6» where
  -- add package configuration options here

lean_lib «LeanXv6» where
  -- add library configuration options here

@[default_target]
lean_exe «lean-xv6» where
  root := `Main
