import { Body, Controller, Get, HttpCode, HttpStatus, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser, Roles } from '../../common/auth/decorators';
import { DriversService } from './drivers.service';
import { CreateDocumentDto, PresignDto, RegisterDriverDto } from './dto/driver.dto';

@ApiTags('driver')
@ApiBearerAuth()
@Roles('driver')
@Controller('driver')
export class DriversController {
  constructor(private readonly drivers: DriversService) {}

  @Post('register')
  @HttpCode(HttpStatus.OK)
  register(@CurrentUser() user: AuthUser, @Body() dto: RegisterDriverDto) {
    return this.drivers.register(user.id, dto);
  }

  @Post('documents/presign')
  @HttpCode(HttpStatus.OK)
  presign(@CurrentUser() user: AuthUser, @Body() dto: PresignDto) {
    return this.drivers.presign(user.id, dto);
  }

  @Post('documents')
  addDocument(@CurrentUser() user: AuthUser, @Body() dto: CreateDocumentDto) {
    return this.drivers.addDocument(user.id, dto);
  }

  @Get('me')
  me(@CurrentUser() user: AuthUser) {
    return this.drivers.me(user.id);
  }
}
