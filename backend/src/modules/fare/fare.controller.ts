import { Body, Controller, HttpCode, HttpStatus, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiProperty, ApiTags } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { ValidateNested } from 'class-validator';
import { Roles } from '../../common/auth/decorators';
import { PlaceDto } from '../../common/geo/geo.dto';
import { FareService } from './fare.service';

export class EstimateDto {
  @ApiProperty({ type: PlaceDto }) @ValidateNested() @Type(() => PlaceDto) pickup: PlaceDto;
  @ApiProperty({ type: PlaceDto }) @ValidateNested() @Type(() => PlaceDto) drop: PlaceDto;
}

@ApiTags('rider')
@ApiBearerAuth()
@Roles('rider')
@Controller('fare')
export class FareController {
  constructor(private readonly fares: FareService) {}

  @Post('estimate')
  @HttpCode(HttpStatus.OK)
  estimate(@Body() dto: EstimateDto) {
    return this.fares.estimate(dto.pickup, dto.drop);
  }
}
