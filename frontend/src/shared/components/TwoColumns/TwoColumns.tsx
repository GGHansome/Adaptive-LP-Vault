import { Row, Col } from 'antd';
import type { TwoColumnsProps } from './interface';
export function TwoColumns({ left, right }: TwoColumnsProps) {
  return (
    <Row gutter={[24, 24]}>
      <Col xs={24} lg={12}>
        {left}
      </Col>
      <Col xs={24} lg={12}>
        {right}
      </Col>
    </Row>
  );
}
