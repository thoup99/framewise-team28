
with FFmpeg.Avformat;

package body FFmpeg.Version is

   function Raw_Version return Natural;

   function Raw_Version return Natural is
   begin
      return Natural (FFmpeg.Avformat.Version);
   end Raw_Version;

   function Get_Major return Natural is
   begin
      return Raw_Version / 65_536;
   end Get_Major;

   function Get_Minor return Natural is
   begin
      return (Raw_Version / 256) mod 256;
   end Get_Minor;

   function Get_Micro return Natural is
   begin
      return Raw_Version mod 256;
   end Get_Micro;

end FFmpeg.Version;
