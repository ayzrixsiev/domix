-- the excel bulk upload is gone. picking a category when a shop is created now stocks its whole
-- catalogue from a template (migration 000005), which is what the spreadsheet existed to avoid, so
-- the dedupe key that upload was built on has nothing left writing to it.
--
-- dropping the column rather than leaving it unused: `article` was never shown anywhere in the app,
-- it only ever held the Артикул out of a spreadsheet cell, and a nullable column no code path fills
-- is a trap for whoever reads this schema next. products already have a stable identity -
-- template_key for the shared basket, the primary key for everything else.
DROP INDEX IF EXISTS idx_products_shop_article;

ALTER TABLE products
DROP COLUMN IF EXISTS article;

-- products.category now holds one of the twelve locale-neutral codes in internal/catalog (mixes,
-- blocks, lumber, ...) instead of russian display text. same reasoning as shops.category and
-- products.availability: the app translates the code, so adding a language never touches the
-- database - and the old text was literally untranslatable, since it stayed russian when the app
-- was switched to uzbek.
--
-- the remap is keyed on template_key, not on the old category text, because the two do not map
-- one-to-one: "Листовые материалы" held plywood (lumber), drywall (finishing) and CD/UD profile
-- (metal) at the same time. template_key identifies the exact item, so this can be exact.
UPDATE products AS p
SET category = t.category
FROM (VALUES
    ('universal.cement_m400', 'mixes'),
    ('universal.cement_m500', 'mixes'),
    ('universal.sand', 'mixes'),
    ('universal.gravel_5_20', 'mixes'),
    ('universal.brick_common', 'blocks'),
    ('universal.brick_facing', 'blocks'),
    ('universal.gasblock', 'blocks'),
    ('universal.foamblock', 'blocks'),
    ('universal.cinderblock', 'blocks'),
    ('universal.osb_9', 'lumber'),
    ('universal.plywood_10', 'lumber'),
    ('universal.drywall_12', 'finishing'),
    ('universal.profile_cd', 'metal'),
    ('universal.profile_ud', 'metal'),
    ('universal.plaster_gypsum', 'mixes'),
    ('universal.putty_finish', 'mixes'),
    ('universal.tile_glue', 'mixes'),
    ('universal.primer_deep', 'mixes'),
    ('universal.paint_water', 'paints'),
    ('universal.enamel_pf115', 'paints'),
    ('universal.foam_750', 'mixes'),
    ('universal.sealant_silicone', 'mixes'),
    ('universal.rebar_12', 'metal'),
    ('universal.masonry_mesh', 'metal'),
    ('universal.angle_50', 'metal'),
    ('universal.pipe_40x20', 'metal'),
    ('universal.nails_100', 'fasteners'),
    ('universal.screws_wood', 'fasteners'),
    ('universal.screws_metal', 'fasteners'),
    ('universal.dowel_6x40', 'fasteners'),
    ('universal.anchor_10x100', 'fasteners'),
    ('universal.mineral_wool_50', 'insulation'),
    ('universal.foam_board_50', 'insulation'),
    ('universal.roofing_felt', 'roofing'),
    ('universal.corrugated_c8', 'roofing'),
    ('universal.metal_tile', 'roofing'),
    ('universal.porcelain_60', 'finishing'),
    ('universal.wall_tile', 'finishing'),
    ('universal.laminate_32', 'finishing'),
    ('universal.linoleum', 'finishing'),
    ('universal.cable_vvg', 'electrical'),
    ('universal.breaker_16a', 'electrical'),
    ('universal.socket', 'electrical'),
    ('universal.switch_1', 'electrical'),
    ('universal.led_lamp_12w', 'electrical'),
    ('universal.ppr_pipe_20', 'plumbing'),
    ('universal.kitchen_mixer', 'plumbing'),
    ('universal.toilet_compact', 'plumbing'),
    ('universal.interior_door', 'finishing'),
    ('universal.pvc_window', 'finishing'),
    ('plumbing.ppr_20', 'plumbing'),
    ('plumbing.ppr_25', 'plumbing'),
    ('plumbing.ppr_32', 'plumbing'),
    ('plumbing.pvc_50', 'plumbing'),
    ('plumbing.pvc_110', 'plumbing'),
    ('plumbing.metalplastic_16', 'plumbing'),
    ('plumbing.corrugation_toilet', 'plumbing'),
    ('plumbing.coupling_20', 'plumbing'),
    ('plumbing.elbow_20', 'plumbing'),
    ('plumbing.tee_20', 'plumbing'),
    ('plumbing.reducer_25_20', 'plumbing'),
    ('plumbing.union_half', 'plumbing'),
    ('plumbing.ball_valve_half', 'plumbing'),
    ('plumbing.ball_valve_three_quarter', 'plumbing'),
    ('plumbing.stop_valve_half', 'plumbing'),
    ('plumbing.coarse_filter', 'plumbing'),
    ('plumbing.check_valve', 'plumbing'),
    ('plumbing.pressure_reducer', 'plumbing'),
    ('plumbing.water_meter', 'plumbing'),
    ('plumbing.mixer_kitchen', 'plumbing'),
    ('plumbing.mixer_basin', 'plumbing'),
    ('plumbing.mixer_bath', 'plumbing'),
    ('plumbing.shower_set', 'plumbing'),
    ('plumbing.shower_rack', 'plumbing'),
    ('plumbing.toilet_compact', 'plumbing'),
    ('plumbing.toilet_installation', 'plumbing'),
    ('plumbing.toilet_seat', 'plumbing'),
    ('plumbing.basin_pedestal', 'plumbing'),
    ('plumbing.basin_counter', 'plumbing'),
    ('plumbing.bath_steel_150', 'plumbing'),
    ('plumbing.bath_acrylic_170', 'plumbing'),
    ('plumbing.shower_tray_90', 'plumbing'),
    ('plumbing.siphon_basin', 'plumbing'),
    ('plumbing.siphon_bath', 'plumbing'),
    ('plumbing.floor_drain_100', 'plumbing'),
    ('plumbing.towel_warmer', 'plumbing'),
    ('plumbing.radiator_alu', 'plumbing'),
    ('plumbing.radiator_bimetal', 'plumbing'),
    ('plumbing.mayevsky_valve', 'plumbing'),
    ('plumbing.boiler_80', 'plumbing'),
    ('plumbing.gas_heater', 'plumbing'),
    ('plumbing.pump_circulation', 'plumbing'),
    ('plumbing.pump_submersible', 'plumbing'),
    ('plumbing.hydro_tank_24', 'plumbing'),
    ('plumbing.flex_hose_50', 'plumbing'),
    ('plumbing.ptfe_tape', 'plumbing'),
    ('plumbing.plumbing_flax', 'plumbing'),
    ('plumbing.sealant_plumbing', 'plumbing'),
    ('plumbing.clamp_20', 'fasteners'),
    ('plumbing.access_hatch', 'plumbing'),
    ('wood.board_25x150', 'lumber'),
    ('wood.beam_100x100', 'lumber'),
    ('wood.beam_50x50', 'lumber'),
    ('wood.batten_20x40', 'lumber'),
    ('wood.lining_conifer', 'lumber'),
    ('wood.floorboard_36', 'lumber'),
    ('wood.plywood_fk_10', 'lumber'),
    ('wood.osb3_9', 'lumber'),
    ('wood.chipboard_16', 'lumber'),
    ('wood.mdf_panel', 'lumber'),
    ('wallpaper.paper', 'finishing'),
    ('wallpaper.vinyl_paper', 'finishing'),
    ('wallpaper.vinyl_fleece', 'finishing'),
    ('wallpaper.fleece_paintable', 'finishing'),
    ('wallpaper.textile', 'finishing'),
    ('wallpaper.liquid', 'finishing'),
    ('wallpaper.photo', 'finishing'),
    ('wallpaper.border', 'finishing'),
    ('wallpaper.glue', 'mixes'),
    ('wallpaper.primer', 'mixes')
) AS t(template_key, category)
WHERE p.template_key = t.template_key;

-- rows the owner added themselves keep whatever category text they were created with. they are not
-- remappable - the value was free text - and blanking them would lose information. the app falls
-- back to displaying an unrecognised value as-is, and the first edit of such a product replaces it
-- with a real code, since the form now offers a fixed list instead of a text field.
