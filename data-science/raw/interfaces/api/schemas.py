from typing import Literal

from pydantic import BaseModel, Field

TipoInmueble = Literal["Casa", "Departamento", "Comercio", "Pyme"]
CalidadAislamiento = Literal["Muy Alta", "Alta", "Media", "Baja", "Muy Baja"]
FuenteEnergia = Literal["Electricidad", "Solar", "Otros"]


class AnalisisRequest(BaseModel):
    """Request del endpoint POST /analisis-energetico.

    4 campos obligatorios.
    7 campos opcionales.
    """

    # OBLIGATORIOS
    consumo_kwh: float = Field(
        ...,
        ge=1,
        le=1000,
        description="Consumo mensual en kWh.",
    )

    cantidad_equipos: int = Field(
        ...,
        ge=1,
        le=100,
        description="Cantidad de equipos o electrodomésticos.",
    )

    tipo_inmueble: TipoInmueble = Field(
        ...,
        description="Tipo de inmueble: Casa | Departamento | Comercio | Pyme.",
    )

    horas_alto_consumo: int = Field(
        ...,
        ge=0,
        le=24,
        description="Horas diarias de alto consumo.",
    )

    # OPCIONALES
    uso_horario_pico: bool | None = Field(
        default=None,
        description="Indica si existe consumo alto en horario pico.",
    )

    metros_cuadrados: int | None = Field(
        default=None,
        ge=26,
        le=2000,
        description="Superficie del inmueble en m².",
    )

    antiguedad_vivienda: int | None = Field(
        default=None,
        ge=0,
        le=150,
        description="Antigüedad de la vivienda en años.",
    )

    zona_fria: bool | None = Field(
        default=None,
        description="Indica si el inmueble se encuentra en una zona fría.",
    )

    calidad_aislamiento: CalidadAislamiento | None = Field(
        default=None,
        description="Calidad del aislamiento térmico.",
    )

    fuente_calefaccion: FuenteEnergia | None = Field(
        default=None,
        description="Fuente de calefacción.",
    )

    fuente_agua_caliente: FuenteEnergia | None = Field(
        default=None,
        description="Fuente utilizada para agua caliente.",
    )
