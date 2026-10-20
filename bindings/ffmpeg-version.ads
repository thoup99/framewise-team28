package FFmpeg.Version is

   function Get_Major return Natural;
   function Get_Minor return Natural;
   function Get_Micro return Natural;

   function Version return String;

end FFmpeg.Version;