--  Bounded, GUI-owned source-in thumbnails. No document edits or history.
with Adi.Image;
with Framewise;

package Timeline_Thumbnails is
   Width  : constant Positive := 64;
   Height : constant Positive := 36;

   --  Return a cached image, or queue a missing key without reading media.
   function Request (Source, File : String; At_Time : Framewise.Time)
      return Adi.Image.Image_Handle;

   --  Complete at most one queued decode. True means drawing should refresh.
   function Process_One return Boolean;

   --  Release images and pending requests before project/proxy replacement.
   procedure Clear;
end Timeline_Thumbnails;
