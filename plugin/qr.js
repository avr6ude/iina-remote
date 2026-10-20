ObjC.import("CoreImage");
ObjC.import("AppKit");

function run([httpPort, wsPort]) {
  const app = Application.currentApplication();
  app.includeStandardAdditions = true;
  const ip = app.doShellScript("/usr/sbin/ipconfig getifaddr \"$(/sbin/route -n get default | /usr/bin/awk '/interface:/{print $2}')\"");
  const url = `http://${ip}:${httpPort}/#${wsPort}`;

  const filter = $.CIFilter.filterWithName("CIQRCodeGenerator");
  filter.setValueForKey($(url).dataUsingEncoding($.NSUTF8StringEncoding), "inputMessage");
  const png = $.NSBitmapImageRep.alloc.initWithCIImage(filter.outputImage)
    .representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $())
    .base64EncodedStringWithOptions(0).js;
  return JSON.stringify({ url, png });
}
