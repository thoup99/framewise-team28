with Interfaces.C;

package FFmpeg.Avformat is

   subtype Version_Int is Interfaces.C.unsigned;

   function Avformat_Version return Version_Int
     with Import, Convention => C, External_Name => "avformat_version";

end FFmpeg.Avformat;