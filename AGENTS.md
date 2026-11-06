# AGENTS.md

Builds libjxl (the JPEG XL reference library) for every common .NET platform and ships the native binaries, with no managed code, as one NuGet package: `LibJxl.Native`. The consumer writes its own P/Invoke binding.

Read `PLAN.md` first: it holds the goal, the constraints and the acceptance criteria. Keep it current as decisions are made.

- Never commit or push unless the user confirms it in that message.
- Do not add tests beyond what `PLAN.md` asks for without asking.
- Comments explain why, never what; one or two lines.
