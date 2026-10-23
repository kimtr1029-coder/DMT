#!/usr/bin/env node

// Minimal local wrapper for the WebAssembly Yosys API used by verify.sh.
import fs from "node:fs";
import path from "node:path";
const yosysModule = process.env.YOSYS_MODULE_PATH || "@yowasp/yosys";
const { runYosys, Exit } = await import(yosysModule);

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const rtlDir = path.join(root, "rtl");
const files = {};
const sourceDirs = [rtlDir];
if (process.env.YOSYS_INCLUDE_TB === "1") sourceDirs.push(path.join(root, "tb"));
if (process.env.YOSYS_EXTRA_SOURCE_DIRS) {
  for (const directory of process.env.YOSYS_EXTRA_SOURCE_DIRS.split(path.delimiter))
    if (directory) sourceDirs.push(path.resolve(directory));
}
for (const sourceDir of sourceDirs) {
  for (const name of fs.readdirSync(sourceDir).filter((n) => n.endsWith(".v") || n.endsWith(".vh"))) {
    files[name] = fs.readFileSync(path.join(sourceDir, name));
  }
}

let stdout = "";
let stderr = "";
const collect = (which) => (chunk) => {
  if (chunk === null) return;
  const text = typeof chunk === "string" ? chunk : new TextDecoder().decode(chunk);
  if (which === "out") stdout += text;
  else stderr += text;
};

const script = process.argv.slice(2).join(" ") ||
  "read_verilog -sv *.v; hierarchy -check -top per_qam_bitloading_pipeline_top_direct_erfc; proc; check";

try {
  const outputs = await runYosys(["-Q", "-p", script], files, {
    stdout: collect("out"),
    stderr: collect("err"),
    synchronously: false,
  });
  if (process.env.YOSYS_OUT_DIR && outputs) {
    const writeTree = (tree, directory) => {
      fs.mkdirSync(directory, { recursive: true });
      for (const [name, value] of Object.entries(tree)) {
        const destination = path.join(directory, name);
        if (typeof value === "object" && !(value instanceof Uint8Array))
          writeTree(value, destination);
        else
          fs.writeFileSync(destination, value);
      }
    };
    writeTree(outputs, path.resolve(process.env.YOSYS_OUT_DIR));
  }
  process.stdout.write(stdout);
  process.stderr.write(stderr);
} catch (error) {
  process.stdout.write(stdout);
  process.stderr.write(stderr);
  if (error instanceof Exit) process.exit(error.code);
  throw error;
}
