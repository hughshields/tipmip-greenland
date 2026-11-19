# TIPMIP-Ice Sheets Readme

*19 November 2026*

## General information

- **Name of contributor(s), affiliation and e-mail address:** Hugh Shields, nikolaus.h.shields.gr@dartmouth.edu, Department of Earth and Planetary Sciences, Dartmouth College; Mathieu Morlighem, mathieu.morlighem@dartmouth.edu, Department of Earth and Planetary Sciences, Dartmouth College
- **Date of submission:** 11/19/2026
- **Ice sheet:** Greenland
- **Modelling group:** Dartmouth
- **Ice-sheet model:** ISSM

---

## Model description

Experiments are performed with the Ice Sheet and Sea-Level System Model (ISSM, Larour et al. 2012)

**[Resolution]** All simulations are performed on a unstructured triangular grid with a resolution ranging from 0.5 km close to the grounding line to 10 km in the ice-sheet interior and with 1 vertical layers.

**[Stress balance]** The stress balance used is the Shelfy-Stream Approximation (MacAyeal, 1989).

**[Ice Rheology / Flow law]** For the ice rheology the Glen flow law is assumed. *[n=3]* The depth-averaged viscosity is computed using an ice hardness from the depth-averaged temperature field of the JPL-ISSM simulation for ISMIP6 (Goelzer et al., 2020)

**[Thermodynamics]** Temperatures within the ice sheet are not computed.

**[Friction law]** Basal friction at the ice base is described by a linear Budd sliding law. *[m=1]* The basal friction coefficient is inverted for using transient calibration (see e.g. Badgeley et al. 2025 and Goldberg et al. 2026) on a regional scale (CW, NW, etc.) over the calibration period 2007-2022. During the transient calibration, we minimize the misfit between predicted and observed velocities on selected fast-flowing glaciers from InSAR (Joughin et al., 2021, NSIDC-0481) between 2008 and 2015 and monthly regional mosaics derived from SAR and optical imagery between 2015-2022 (Joughin et al., 2021, NSIDC-0731). Regularization in the cost function is determined using an L-curve.

**[Grounding line]** The grounding line evolves freely, and its position is determined using a hydrostatic floatation criterion. Friction at the grounding line is interpolated on a sub-grid scale (Serousi et al. 2014). Basal melt at the grounding line is interpolated using a sub-grid scheme (Seroussi and Morlighem, 2018).

**[Calving]** The ice front (also simulated at subgrid scale using the levelset method, see via the level-set method, see Bondzio et al. 2016) evolves freely, and calving follows the von-Mises calving law (Morlighem et al. 2016). The law's tunable parameter, $\sigma_{max}$, is calibrated for each individual glacial catchment to match the evolvolution of observed monthly ice front positions from Greene et al. (2024) from 2007-2022.

**[Sub-shelf melting, in particular, for Antarctic Ice Sheet]** Sub-shelf melting follows a linear melt parameterization with parameters from Holmes et al. (2025).

**[Frontal melting, in particular, for Greenland Ice Sheet]** Frontal melting is determined by the ISMIP6 submarine melt implementation (Slater et al., 2020), using the dynamically computed frontal areas and parameters recommended by ISMIP7 *[$\alpha=0.39$, $\Beta=1.19$]*. Ocean thermal forcing is determined using the provided anomalies and the thermal forcings from EN4 (from ISMIP7) over a reference period of 1992-2021 (adjusted to pre-industrial). The subglacial discharge is computed by integrating runoff dynamically from the SMB model. Note that because the SMB model provides yearly values, the seasonal cycle is not captured (and thus the non-linear response from the Slater parameterization).

<mark>**[GIA]** Glacial isostatic adjustment is included using {Elastic Lithosphere-Relaxed Asthenosphere (ELRA) model (Le Meur & Huybrechts, 1996) / …}. *[Please include relevant parameters and their values, e.g. asthenosphere relaxation time, flexural rigidity of the lithosphere.]*</mark>
**NOT YET INCLUDED**

**[Surface mass balance]** Surface melt and runoff are determined using a positive-degree-day (PDD) approach using the SICOPOLIS implementation (see Calov and Greve 2005) and monthly anomalies. *[The PDD ice factor is 7.28, and PDD snow factor is 2.73]*. Monthly precipitation and temperature are computed using the provided rations/anomalies and a climatology from ISMIP7 provided RACMO2.3p2 near surface air temperature and precipitation between 1992-2021, adjusted to pre-industrial. To account for the surface melt–elevation feedback, the near-surface air temperature is corrected for changes in the ice-sheet surface elevation based on a spatially-uniform and time-independent atmospheric lapse rate of 6 °C km⁻¹.

**[Initialization, including approach and datasets]** The model is initialized using a transient claibration. The initial ice-sheet state is associated with the year 2007. The initial ice-sheet geometry and bed topography are based on BedMachine v6 (Morlighem et al., 2025). The transient calibration tuned the friction coefficient to fit observed velocities on selected fast-flowing glaciers from InSAR (Joughin et al., 2021, NSIDC-0481) between 2008 and 2015 and monthly regional mosaics derived from SAR and optical imagery between 2015-2022 (Joughin et al., 2021, NSIDC-0731), using monthly fronts from Greene et al. (2024) and RACMO2.3p2 (Noël et al., 2019) SMB as boundary conditions.


**[Boundary conditions (other than forcing), e.g. geothermal heat flux]** No geothermal heat flux is used.

---

## Relevant constants

- Density of ice: 917 kg/m^3
- Density of ocean water: 1027 kg/m^3
- Density of freshwater: 1000 kg/m^3
- Gravitational acceleration: 9.81 m/s^2

---

## References
Badgeley, J. A., Morlighem, M., & Seroussi, H. (2025). Increased sea-level contribution from northwestern Greenland for models that reproduce observations. *Proceedings of the National Academy of Sciences, 122*(25), e2411904122. [https://doi.org/10.1073/pnas.2411904122](https://doi.org/10.1073/pnas.2411904122)

Bondzio, J. H., et al. (2016). Modelling calving front dynamics using a level-set method: application to Jakobshavn Isbræ, West Greenland. *The Cryosphere, 10*, 497–510. [https://doi.org/10.5194/tc-10-497-2016](https://doi.org/10.5194/tc-10-497-2016)

Calov, R., & Greve, R. (2005). A semi-analytical solution for the positive degree-day model with stochastic temperature variations. *Journal of Glaciology, 51*(172), 173–175. [https://doi.org/10.3189/172756505781829601](https://doi.org/10.3189/172756505781829601)

Goelzer, H., et al. (2020). The future sea-level contribution of the Greenland ice sheet: a multi-model ensemble study of ISMIP6. *The Cryosphere, 14*, 3071–3096. [https://doi.org/10.5194/tc-14-3071-2020](https://doi.org/10.5194/tc-14-3071-2020)

Goldberg, D. N., Morlighem, M., & Gourmelen, N. (2026). Recent observations of Thwaites Glacier, West Antarctica are consistent with high rates of loss in next 50 years. *Geophysical Research Letters, 53*, e2025GL118823. [https://doi.org/10.1029/2025GL118823](https://doi.org/10.1029/2025GL118823)

Greene, C. A., et al. (2024). Ubiquitous acceleration in Greenland Ice Sheet calving from 1985 to 2022. *Nature, 625*, 523–528. [https://doi.org/10.1038/s41586-023-06863-2](https://doi.org/10.1038/s41586-023-06863-2)

Holmes, F. A., Barnett, J., Åkesson, H., Morlighem, M., Nilsson, J., Kirchner, N., & Jakobsson, M. (2025). Sea level rise contribution from Ryder Glacier in northern Greenland varies by an order of magnitude by 2300 depending on future emissions. *The Cryosphere, 19*, 2695–2714. [https://doi.org/10.5194/tc-19-2695-2025](https://doi.org/10.5194/tc-19-2695-2025)

Joughin, I. (2021). *MEaSUREs Greenland Monthly Ice Sheet Velocity Mosaics from SAR and Landsat, Version 3* (NSIDC-0731) [Dataset]. NASA National Snow and Ice Data Center Distributed Active Archive Center. [https://doi.org/10.5067/YDLH5QG02XKC](https://doi.org/10.5067/YDLH5QG02XKC)

Joughin, I., Howat, I., Smith, B., & Scambos, T. (2021). *MEaSUREs Greenland Ice Velocity: Selected Glacier Site Velocity Maps from InSAR, Version 4* (NSIDC-0481) [Dataset]. NASA National Snow and Ice Data Center Distributed Active Archive Center. [https://doi.org/10.5067/GQZQY2M5507Z](https://doi.org/10.5067/GQZQY2M5507Z)

Larour, E., Seroussi, H., Morlighem, M., & Rignot, E. (2012). Continental scale, high order, high spatial resolution, ice sheet modeling using the Ice Sheet System Model (ISSM). *Journal of Geophysical Research: Earth Surface, 117*, F01022. [https://doi.org/10.1029/2011JF002140](https://doi.org/10.1029/2011JF002140)

MacAyeal, D. R. (1989). Large-scale ice flow over a viscous basal sediment: Theory and application to Ice Stream B, Antarctica. *Journal of Geophysical Research, 94*(B4), 4071–4087. [https://doi.org/10.1029/JB094iB04p04071](https://doi.org/10.1029/JB094iB04p04071)

Morlighem, M., et al. (2016). Modeling of Store Gletscher's calving dynamics, West Greenland, in response to ocean thermal forcing. *Geophysical Research Letters, 43*, 2659–2666. [https://doi.org/10.1002/2016GL067695](https://doi.org/10.1002/2016GL067695)

Morlighem, M., et al. (2025). *IceBridge BedMachine Greenland, Version 6* (IDBMG4) [Dataset]. NASA National Snow and Ice Data Center Distributed Active Archive Center. [https://doi.org/10.5067/6B6B225B8V2D](https://doi.org/10.5067/6B6B225B8V2D)

Noël, B., van de Berg, W. J., Lhermitte, S., & van den Broeke, M. R. (2019). Rapid ablation zone expansion amplifies north Greenland mass loss. *Science Advances, 5*(9), eaaw0123. [https://doi.org/10.1126/sciadv.aaw0123](https://doi.org/10.1126/sciadv.aaw0123)

Seroussi, H., & Morlighem, M. (2018). Representation of basal melting at the grounding line in ice flow models. *The Cryosphere, 12*, 3085–3096. [https://doi.org/10.5194/tc-12-3085-2018](https://doi.org/10.5194/tc-12-3085-2018)

Seroussi, H., Morlighem, M., Larour, E., Rignot, E., & Khazendar, A. (2014). Hydrostatic grounding line parameterization in ice sheet models. *The Cryosphere, 8*, 2075–2087. [https://doi.org/10.5194/tc-8-2075-2014](https://doi.org/10.5194/tc-8-2075-2014)

Slater, D. A., et al. (2020). Twenty-first century ocean forcing of the Greenland ice sheet for modelling of sea level contribution. *The Cryosphere, 14*, 985–1008. [https://doi.org/10.5194/tc-14-985-2020](https://doi.org/10.5194/tc-14-985-2020)
