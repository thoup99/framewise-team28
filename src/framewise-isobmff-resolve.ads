--  Week 3 / P2 steps 4 and 5: turn the raw tables of one track into the
--  finished samples of a Track, and check that every one lies inside mdat.
--
--  Framewise.ISOBMFF.Tables copies the tables out of the file as they
--  are. This package is the next stage: it first checks that the tables
--  agree with each other, then walks them to work out each sample's file
--  offset, size and start time.
--
--  OFFSETS: Sample.Offset, Mdat_First and Mdat_Last are 0-based byte
--  offsets, counted from the first byte of the file. That is how stco,
--  co64 and ffprobe's "pos" count. (The box reader's positions are
--  1-based array indices, so Parse subtracts 1 when it finds mdat.)
--
--  AUDIO: one chunk becomes one Sample, as Framewise.ISOBMFF.Tables
--  explains. Its Size is the bytes of all the PCM samples in the chunk,
--  and its Start is the time of the first of them.
--
--  No I/O and no heap allocation.

with Framewise.ISOBMFF.Tables;

package Framewise.ISOBMFF.Resolve with SPARK_Mode is

   function Tables_Agree (Raw : Tables.Raw_Track) return Boolean;
   --  Step 2: True when the tables of Raw fit together:
   --    * the stts run counts add up to the stsz Sample_Count;
   --    * a stsz list has exactly one size per sample;
   --    * the stsc runs start at chunk 1, go up strictly, point only at
   --      chunks stco/co64 really has, and each says at least 1 sample;
   --    * the samples stsc puts in the chunks add up to Sample_Count.
   --  An empty track (all counts 0) agrees.

   procedure Resolve_Track
     (Raw        : Tables.Raw_Track;
      Mdat_First : Natural;
      Mdat_Last  : Natural;
      T          : in out Track;
      Track_End  : out Time;
      Ok         : out Boolean)
     with Post => (if Ok then Track_OK (T, Mdat_First, Mdat_Last));
   --  Fills T from Raw. Raw.Codec says what kind of track it is: None
   --  gives an empty track, PCM_S16 the one-chunk-one-sample rule.
   --  Track_End is when the last sample ends, in Framewise ticks.
   --
   --  Ok = False, T.Count = 0 and Track_End = 0 when: the timescale is 0;
   --  the tables do not agree (Tables_Agree); a sample does not lie
   --  inside Mdat_First .. Mdat_Last; or a time or byte sum would not fit
   --  its type. T is "in out" for the same reason as in Read_Tables: only
   --  T.Samples (1 .. T.Count) is written, never the whole 1 MB array.

end Framewise.ISOBMFF.Resolve;
