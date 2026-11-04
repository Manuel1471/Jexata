# Security policy

## Supported versions

Security fixes target the latest 1.0.x release. Earlier development commits are not maintained separately.

## Evaluating untrusted expressions

Compile with limits for source size, token count, and nesting. Use `Jexata.evaluate_bounded/3` for expressions supplied by untrusted users. It isolates evaluation in a BEAM process and applies a deadline, process heap limit, result-size limit, optional BEAM reduction budget, function-depth limit, and regex match and recursion limits. The copied input and bindings consume the worker's heap budget. Choose limits for the largest valid input your application accepts.

This is resource containment, not a full sandbox. There is no exact JSONata instruction count or independent cap on every intermediate collection. The optional reduction budget is checked periodically while the worker runs and once it completes, so it can overshoot before termination. An expression may still consume CPU until its deadline or allocate up to its heap limit. Apply application-level admission rules and isolate the host if stronger guarantees are required.

## Reporting

Please report security issues privately through the repository's GitHub Security page when private vulnerability reporting is available. Avoid putting exploit details in a public issue.
