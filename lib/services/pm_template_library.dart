/// Standard PM task templates keyed on the equipment friendly name that
/// [IfcParser] stores as [Equipment.typeName]. Each entry defines one
/// maintenance activity with a default interval; a single piece of
/// equipment typically has 1–3 tasks generated from it.
class PmTemplate {
  final String intervention;
  final int frequencyMonths;
  const PmTemplate(this.intervention, this.frequencyMonths);
}

class PmTemplateLibrary {
  PmTemplateLibrary._();

  static const Map<String, List<PmTemplate>> _byTypeName = {
    // ── HVAC ────────────────────────────────────────────────────────────────
    'Air Terminal': [
      PmTemplate('Clean and inspect grilles/diffusers', 12),
    ],
    'Air Terminal Box': [
      PmTemplate('Inspect, test and calibrate VAV box actuator', 12),
    ],
    'Heat Recovery Unit': [
      PmTemplate('Clean heat-exchanger plates and inspect seals', 6),
      PmTemplate('Full service: replace filters, check bearings and drives', 12),
    ],
    'Boiler': [
      PmTemplate('Safety valve lift test and flue gas analysis', 6),
      PmTemplate('Full annual service: clean heat exchangers, test controls and safety devices', 12),
    ],
    'Burner': [
      PmTemplate('Clean burner assembly and check combustion', 6),
      PmTemplate('Full service: replace consumables, test safety interlocks', 12),
    ],
    'Chiller': [
      PmTemplate('Check refrigerant charge and inspect for leaks', 6),
      PmTemplate('Clean condenser coils, test controls and safety devices', 12),
    ],
    'Coil': [
      PmTemplate('Clean coil surfaces and check for blockages', 6),
      PmTemplate('Inspect coil for corrosion and refrigerant leaks', 12),
    ],
    'Compressor': [
      PmTemplate('Check oil level and inspect for leaks', 3),
      PmTemplate('Oil and filter change, vibration analysis', 6),
    ],
    'Condenser': [
      PmTemplate('Clean condenser fins and check refrigerant charge', 6),
    ],
    'Chilled Beam': [
      PmTemplate('Clean and inspect chilled beam coil and connections', 12),
    ],
    'Cooling Tower': [
      PmTemplate('Clean basin and inspect fill packing and drift eliminators', 3),
      PmTemplate('Full inspection: fans, structure, water treatment and legionella control', 6),
    ],
    'Damper': [
      PmTemplate('Test operation, inspect blades and lubricate linkages', 12),
    ],
    'Evaporative Cooler': [
      PmTemplate('Clean cooling pads and sump', 3),
      PmTemplate('Full service: replace pads, inspect pump and fan', 12),
    ],
    'Evaporator': [
      PmTemplate('Clean evaporator and check refrigerant charge', 6),
    ],
    'Fan': [
      PmTemplate('Inspect belts, tension and alignment', 3),
      PmTemplate('Lubricate bearings and inspect impeller', 6),
    ],
    'Filter': [
      PmTemplate('Replace or clean air filter', 3),
    ],
    'Heat Exchanger': [
      PmTemplate('Clean heat-exchanger and inspect connections', 6),
      PmTemplate('Full inspection and pressure test', 12),
    ],
    'Humidifier': [
      PmTemplate('Clean, descale and disinfect humidifier', 3),
      PmTemplate('Full service: replace consumables and test controls', 12),
    ],
    'Space Heater': [
      PmTemplate('Clean and inspect space heater, test controls', 12),
    ],
    'Tube Bundle': [
      PmTemplate('Clean tube bundle and inspect for fouling', 12),
    ],
    'Unitary Equipment': [
      PmTemplate('Replace or clean air filter', 3),
      PmTemplate('Full service: clean coils, check refrigerant, test controls', 12),
    ],

    // ── Plumbing ─────────────────────────────────────────────────────────────
    'Sanitary Fixture': [
      PmTemplate('Inspect, clean and descale sanitary fixture', 12),
    ],
    'Waste Terminal': [
      PmTemplate('Inspect and flush waste terminal, check trap seal', 6),
    ],
    'Stack Terminal': [
      PmTemplate('Inspect stack terminal and ensure clear flow', 12),
    ],
    'Interceptor': [
      PmTemplate('Pump, clean and inspect interceptor', 6),
    ],
    'Tank': [
      PmTemplate('Clean, inspect and test tank and associated controls', 12),
      PmTemplate('Check sacrificial anode and water quality', 24),
    ],
    'Valve': [
      PmTemplate('Exercise valve through full stroke and lubricate', 12),
    ],
    'Flow Meter': [
      PmTemplate('Calibrate and inspect flow meter', 12),
    ],

    // ── Mechanical ───────────────────────────────────────────────────────────
    'Pump': [
      PmTemplate('Check vibration, noise and seals', 3),
      PmTemplate('Lubricate bearings and inspect mechanical seal', 6),
      PmTemplate('Full overhaul: inspect impeller, wear rings and shaft', 12),
    ],
    'Engine': [
      PmTemplate('Check oil level, coolant and belts', 3),
      PmTemplate('Oil and filter change, inspect fuel system', 6),
      PmTemplate('Full service: replace timing belts, test governor and controls', 12),
    ],
    'Lift / Escalator': [
      PmTemplate('Monthly safety check and lubrication', 1),
      PmTemplate('Full annual service and statutory inspection', 12),
    ],
    'Medical Device': [
      PmTemplate('Service per manufacturer specification and calibrate', 12),
    ],
    'Actuator': [
      PmTemplate('Test full travel and inspect actuator and linkages', 12),
    ],
    'Controller': [
      PmTemplate('Test inputs/outputs and inspect controller housing', 12),
    ],
    'Control Panel': [
      PmTemplate('Inspect connections, test controls and clean panel interior', 12),
    ],
    'Instrument': [
      PmTemplate('Calibrate instrument and inspect connections', 12),
    ],
    'Sensor': [
      PmTemplate('Test response and calibrate sensor', 12),
    ],

    // ── Electrical ───────────────────────────────────────────────────────────
    'Electric Appliance': [
      PmTemplate('PAT test and visual inspection', 12),
    ],
    'Distribution Board': [
      PmTemplate('Inspect connections, tighten terminals and check for overheating', 6),
      PmTemplate('Test RCDs, MCBs and isolators; thermal imaging survey', 12),
    ],
    'Distribution Point': [
      PmTemplate('Inspect connections and test protective devices', 12),
    ],
    'Battery / UPS': [
      PmTemplate('Test battery capacity and check charger output', 6),
      PmTemplate('Full service: replace batteries if below 80% capacity, test on load', 12),
    ],
    'Generator': [
      PmTemplate('Check oil, coolant and fuel; run weekly test', 1),
      PmTemplate('Oil and filter change, inspect belts and connections', 6),
      PmTemplate('Full load test and annual service', 12),
    ],
    'Electric Motor': [
      PmTemplate('Lubricate bearings and check alignment', 6),
      PmTemplate('Insulation resistance test and thermal survey', 12),
    ],
    'Time Control': [
      PmTemplate('Test and re-synchronise time control settings', 12),
    ],
    'Lamp': [
      PmTemplate('Replace lamp and clean fitting', 12),
    ],
    'Light Fixture': [
      PmTemplate('Clean fitting and inspect for damage', 12),
    ],
    'Outlet': [
      PmTemplate('Visual inspection and PAT test of outlet', 24),
    ],
    'Protective Device': [
      PmTemplate('Trip test and inspect contact condition', 12),
    ],
    'Tripping Unit': [
      PmTemplate('Test tripping unit under simulated fault conditions', 12),
    ],
    'Switch': [
      PmTemplate('Inspect and operate switching device; check contacts', 12),
    ],
    'Transformer': [
      PmTemplate('Check temperature, cooling and inspect for oil leaks', 6),
      PmTemplate('Oil sampling and dielectric test, insulation resistance test', 12),
    ],
    'Solar Device': [
      PmTemplate('Clean solar panels and inspect mountings', 6),
      PmTemplate('Test output, inspect inverter and connections', 12),
    ],
    'Motor Connection': [
      PmTemplate('Inspect motor connection terminals and check for overheating', 12),
    ],

    // ── Safety ───────────────────────────────────────────────────────────────
    'Alarm': [
      PmTemplate('Test alarm sounder and detector response', 6),
      PmTemplate('Full inspection, test all zones and update log', 12),
    ],
    'Fire Suppression Terminal': [
      PmTemplate('Inspect sprinkler heads, pipes and valves for obstructions', 6),
      PmTemplate('Full pressure test and flow test of suppression system', 12),
    ],

    // ── IT Equipment ─────────────────────────────────────────────────────────
    'Communications Appliance': [
      PmTemplate('Inspect connections, clean vents and test comms links', 12),
    ],
    'Audio-Visual Appliance': [
      PmTemplate('Inspect, clean and test audio-visual equipment', 12),
    ],
  };

  /// IFC2X3 generic class friendly names that carry no specific maintenance
  /// template — these go to the review queue for the user to decide.
  static const Set<String> _genericIfc2x3Names = {
    'Flow Terminal',
    'Flow Controller',
    'Flow Moving Device',
    'Storage Device',
    'Treatment Device',
    'Energy Conversion Device',
    'Control Element',
    'Equipment', // IfcBuildingElementProxy
  };

  /// Returns the templates for [typeName], or null if none are defined.
  static List<PmTemplate>? templatesFor(String? typeName) {
    if (typeName == null || typeName.isEmpty) return null;
    return _byTypeName[typeName];
  }

  /// True if [typeName] has at least one template.
  static bool hasTemplate(String? typeName) => templatesFor(typeName) != null;

  /// True if [typeName] is a generic IFC2X3 placeholder that should go to the
  /// review queue rather than being silently skipped.
  static bool isGenericPlaceholder(String? typeName) =>
      typeName != null && _genericIfc2x3Names.contains(typeName);
}
