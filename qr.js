ObjC.import("CoreImage");
ObjC.import("AppKit");

function run([httpPort, wsPort]) {
  const app = Application.currentApplication();
  app.includeStandardAdditions = true;
  const ip = app.doShellScript("/usr/sbin/ipconfig getifaddr \"$(/sbin/route -n get default | /usr/bin/awk '/interface:/{print $2}')\"");
  const url = `http://${ip}:${httpPort}/#${wsPort}`;

  const filter = $.CIFilter.filterWithName("CIQRCodeGenerator");
  filter.setValueForKey($(url).dataUsingEncoding($.NSUTF8StringEncoding), "inputMessage");
  // One pixel per module; the sidebar draws them as an SVG so they stay square at any size.
  const bitmap = $.NSBitmapImageRep.alloc.initWithCIImage(filter.outputImage);
  const modules = [];
  for (let y = 0; y < bitmap.pixelsHigh; y++) {
    let row = "";
    for (let x = 0; x < bitmap.pixelsWide; x++) row += bitmap.colorAtXY(x, y).redComponent < 0.5 ? "1" : "0";
    modules.push(row);
  }
  return JSON.stringify({ url, modules });
}
