# Phase log

Rewritten after an audit: the earlier log claimed results the code did not produce.

- Phase 0-2: skeleton, preflight, synthetic generator (real photos, correctly rendered text), metrics. Done.
- Phase 3 (detection): rewritten evidence map and classifier. Mask F1 0.08-0.27 on synthetic; **gate not met**. w4 finds 7/7 logos.
- Phase 4 (removal): M3 reaches about 35 dB in-mask with oracle masks (baseline about 18 dB); a0 error about 0.01. **Gate met with oracle masks only.**
- Phase 5: `run_all` runs; 10/10 unit tests pass (testLattice assumed the wrong vector order; fixed; testClassifyPeriodic original fixture restored).
- Phase 6: report rewritten from `results/metrics.csv`.
