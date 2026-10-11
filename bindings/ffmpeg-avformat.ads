with Interfaces.C;

package FFmpeg.Avformat is

   function Version return Interfaces.C.unsigned;

   pragma Import
     (Convention    => C,
      Entity        => Version,
      External_Name => "avformat_version");

end FFmpeg.Avformat;