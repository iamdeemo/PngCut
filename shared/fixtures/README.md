# Shared fixture paths

契约案例中的路径均为逻辑路径，使用正斜杠分隔。测试必须为每个案例创建独立的临时根目录，并将逻辑路径映射到该根目录之下；不得依赖开发机上的固定绝对路径。

`platforms` 包含 `all` 的案例必须在 macOS 和 Windows 上执行。平台专属案例仅当 `platforms` 包含当前平台标识（`macos` 或 `windows`）时执行。测试结束后应删除其临时根目录。
