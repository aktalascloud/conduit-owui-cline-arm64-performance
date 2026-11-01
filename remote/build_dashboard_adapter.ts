// Build only our adapter; the installed Cline checkout and executable are read-only.
import {resolve} from "node:path";
const [source, output] = process.argv.slice(2);
if (!source || !output) throw new Error("Usage: bun build_dashboard_adapter.ts CLINE_SOURCE OUTPUT_EXE");
const server = resolve(source, "apps/cline-hub/src/server.ts");
const helper = resolve(import.meta.dir, "session_model.ts");
const entry=output+".entry.ts";
await Bun.write(entry,`import {startClineHubDashboardServer} from ${JSON.stringify(server)}; await startClineHubDashboardServer();`);
const result = await Bun.build({entrypoints:[entry], target:"bun", minify:true,
  compile:{target:"bun-windows-x64-baseline", outfile:output},
  plugins:[{name:"conduit-session-model", setup(build) {
    build.onLoad({filter:/[\\/]cline-hub[\\/]src[\\/]server[\\/]sessions\.ts$/}, async args => {
      const text=await Bun.file(args.path).text();
      if(!text.includes("function buildStartInputFromSession(")) throw new Error("Pinned resume helper changed");
      return {contents:text.replace("function buildStartInputFromSession(","export function buildStartInputFromSession("),loader:"ts"};
    });
    build.onLoad({filter:/[\\/]cline-hub[\\/]src[\\/]server\.ts$/}, async args => {
      let text = await Bun.file(args.path).text();
      const old = /const result = await handleDesktopCommand\(\s*ctx,\s*frame.command,\s*frame.args,\s*\);/;
      if (!old.test(text)) throw new Error("Pinned dashboard handler changed; review required");
      text = text.replace("CORE_BUILD_VERSION", "CORE_BUILD_VERSION, getLocalProviderModels");
      text = text.replace("\twebviewDistDir,", "\twebviewDistDir, providerSettingsManager,");
      text = `import {buildStartInputFromSession} from "./server/sessions";\n` + text;
      text = `import {changeSessionModel} from ${JSON.stringify(helper)};\n` + text;
      text = text.replace(old, `const result = frame.command === "conduit_set_session_model"
        ? await changeSessionModel(ctx,peer,frame.args,{models:getLocalProviderModels,settings:providerSettingsManager,resume:buildStartInputFromSession})
        : await handleDesktopCommand(ctx,frame.command,frame.args);`);
      return {contents:text,loader:"ts"};
    });
  }}]});
await Bun.file(entry).delete();
if (!result.success) {console.error(result.logs);process.exit(1);}
