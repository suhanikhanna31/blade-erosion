# ANSYS Static Structural Step

## Inputs produced automatically by the pipeline

Running `scripts/pipeline_orchestrator.m` writes two files into this folder:

- `boundary_condition_export.csv` — plain-text record of the erosion coordinate,
  pitting depth, peak rotor bending moment, derived equivalent applied force,
  and the 250 MPa yield limit.
- `boundary_condition.mac` — the same data as an APDL command snippet
  (`*SET` parameters) that a Workbench **Commands** object can reference
  directly, so the load is imported without manual UI re-entry (REQ-SYS-01).

## Manual steps in ANSYS Workbench (outside MATLAB's reach)

1. Open (or create) the **Static Structural** project containing the 3D CAD
   blade geometry.
2. Create/select a named selection `ErosionZone` at the erosion coordinate
   reported in `boundary_condition_export.csv` (radial position from root).
3. Insert a **Commands (APDL)** object under the Static Structural branch and
   point it at `boundary_condition.mac`, or paste its contents in.
4. Apply a **Fixed Support** at the blade root, and a **Force**/**Pressure**
   boundary condition on `ErosionZone` using `APPLIED_FORCE_N`.
5. Solve, then plot **Equivalent (von-Mises) Stress**.
6. Confirm the local peak at the erosion coordinate stays below the
   `YIELD_LIMIT_MPA` (250 MPa) parameter — this is the live check for
   **REQ-FEA-03**.
7. Export a screenshot of the stress contour as
   `reports/figures/graphB_ansys_stress_contour.png` (replacing the
   placeholder described below) and update `README.md`'s pass/fail line for
   REQ-FEA-03 with the actual solved value.

## About `reports/figures/graphB_ansys_stress_contour_MOCK.png`

This repository does not have an ANSYS license available in the environment
that assembled it, so this image is a **clearly labeled conceptual mock-up**
generated in Python/matplotlib — it shows the *expected shape* of the
deliverable (stress heat map on the blade planform, callout arrow at the
erosion coordinate, colorbar with the 250 MPa limit marked) so the README
layout and reviewers know exactly what to look for. It is not a real FEA
result and should not be cited as structural evidence. Swap it for your real
ANSYS export before treating REQ-FEA-03 as verified.
